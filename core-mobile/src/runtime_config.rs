//! 生成交给嵌入式 mihomo 的运行时配置。
//!
//! 复用桌面端：`merge_yaml`（覆盖层合并）、`restore_security_settings`（钉死控制面、清掉
//! unix/pipe/TLS/CORS/DoH/外部 UI 等不受管入口）、`quote_short_id_values`（订阅正文入库时已做）。
//! 移动端特有（桌面端没有）：控制面只走 App 私有目录下的 unix socket，不开 TCP 端口；
//! TUN 由系统 VPN 框架提供 fd（Android VpnService / iOS NEPacketTunnelProvider）；内存相关的保守默认值。

use crate::error::MobileError;
use serde_yaml::{Mapping, Value};
use zephyr_core::config::merge::{merge_yaml, restore_security_settings, SecuritySettings};

#[derive(Debug, Clone, Copy, PartialEq, Eq, uniffi::Enum)]
pub enum TunStackKind {
    System,
    Gvisor,
    Mixed,
}

#[derive(Debug, Clone, PartialEq, uniffi::Record)]
pub struct DnsConfig {
    pub fake_ip: bool,
    pub nameservers: Vec<String>,
    pub fallback: Vec<String>,
    pub ipv6: bool,
}

#[derive(Debug, Clone, PartialEq, uniffi::Record)]
pub struct TunConfig {
    pub stack: TunStackKind,
    pub mtu: i32,
    pub ipv6: bool,
    pub strict_route: bool,
    /// 系统 VPN 框架交来的 TUN fd；None = 不开 TUN（仅本地代理，调试用）
    pub file_descriptor: Option<i32>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, uniffi::Enum)]
pub enum ProxyMode {
    Rule,
    Global,
    Direct,
}

#[derive(Debug, Clone, uniffi::Record)]
pub struct RuntimeOptions {
    pub dns: DnsConfig,
    pub tun: TunConfig,
    pub mode: ProxyMode,
    /// external-controller-unix 路径（App Group / 私有目录内）
    pub controller_socket: String,
    /// iOS 扩展里关掉进程识别（系统不给），Android 可开
    pub find_process: bool,
    pub log_level: String,
}

fn s(v: &str) -> Value {
    Value::String(v.into())
}

fn overlay(o: &RuntimeOptions) -> Value {
    let mut m = Mapping::new();
    m.insert(s("mode"), s(match o.mode {
        ProxyMode::Rule => "rule",
        ProxyMode::Global => "global",
        ProxyMode::Direct => "direct",
    }));
    m.insert(s("log-level"), s(&o.log_level));
    m.insert(s("ipv6"), Value::Bool(o.dns.ipv6 || o.tun.ipv6));
    m.insert(s("allow-lan"), Value::Bool(false));
    m.insert(s("unified-delay"), Value::Bool(true));
    m.insert(s("tcp-concurrent"), Value::Bool(true));
    m.insert(s("find-process-mode"), s(if o.find_process { "strict" } else { "off" }));
    // 本地监听端口全部关掉：流量只从 TUN 进
    for k in ["port", "socks-port", "mixed-port", "redir-port", "tproxy-port"] {
        m.insert(s(k), Value::Null);
    }
    let mut profile = Mapping::new();
    profile.insert(s("store-selected"), Value::Bool(true));
    profile.insert(s("store-fake-ip"), Value::Bool(o.dns.fake_ip));
    m.insert(s("profile"), Value::Mapping(profile));

    let list = |v: &[String]| Value::Sequence(v.iter().map(|x| s(x)).collect());
    let mut dns = Mapping::new();
    dns.insert(s("enable"), Value::Bool(true));
    dns.insert(s("ipv6"), Value::Bool(o.dns.ipv6));
    dns.insert(s("enhanced-mode"), s(if o.dns.fake_ip { "fake-ip" } else { "redir-host" }));
    if o.dns.fake_ip {
        dns.insert(s("fake-ip-range"), s("198.18.0.1/16"));
    }
    dns.insert(s("nameserver"), list(&o.dns.nameservers));
    dns.insert(s("fallback"), if o.dns.fallback.is_empty() { Value::Null } else { list(&o.dns.fallback) });
    m.insert(s("dns"), Value::Mapping(dns));

    let mut tun = Mapping::new();
    match o.tun.file_descriptor {
        Some(fd) => {
            tun.insert(s("enable"), Value::Bool(true));
            tun.insert(s("stack"), s(match o.tun.stack {
                TunStackKind::System => "system",
                TunStackKind::Gvisor => "gvisor",
                TunStackKind::Mixed => "mixed",
            }));
            tun.insert(s("file-descriptor"), Value::Number(fd.into()));
            tun.insert(s("mtu"), Value::Number(o.tun.mtu.clamp(1280, 65535).into()));
            tun.insert(s("inet6-address"), if o.tun.ipv6 { Value::Sequence(vec![s("fdfe:dcba:9876::1/126")]) } else { Value::Null });
            tun.insert(s("strict-route"), Value::Bool(o.tun.strict_route));
            // 路由由系统 VPN 框架设置，mihomo 不碰路由表
            tun.insert(s("auto-route"), Value::Bool(false));
            tun.insert(s("auto-detect-interface"), Value::Bool(false));
            // 复用桌面端：dns-hijack 同时劫持 UDP 与 TCP 53
            zephyr_core::config::tun::ensure_dns_hijack_entries(&mut tun);
        }
        None => {
            tun.insert(s("enable"), Value::Bool(false));
        }
    }
    m.insert(s("tun"), Value::Mapping(tun));
    Value::Mapping(m)
}

/// 场景注入计划（由 MobileCore 根据场景/覆写/例外算出）。
#[derive(Debug, Default, Clone)]
pub struct ScenePlan {
    /// 注入的代理定义（name 已改成 member 名）
    pub proxies: Vec<Value>,
    /// (组名, 成员)；成员空时放 DIRECT
    pub groups: Vec<(String, Vec<String>)>,
    /// 前插规则（覆写 → 例外 → 场景应用）
    pub rules_front: Vec<String>,
    /// "其他"场景接管 MATCH
    pub match_target: Option<String>,
}

fn apply_plan(m: &mut Mapping, plan: &ScenePlan) {
    let seq = |m: &mut Mapping, k: &str| -> Vec<Value> {
        match m.remove(s(k)) {
            Some(Value::Sequence(v)) => v,
            _ => vec![],
        }
    };
    let mut proxies = seq(m, "proxies");
    let mut taken: std::collections::HashSet<String> = proxies.iter().filter_map(|p| p.get("name").and_then(|n| n.as_str()).map(String::from)).collect();
    for p in &plan.proxies {
        let n = p.get("name").and_then(|n| n.as_str()).unwrap_or_default().to_string();
        if taken.insert(n) {
            proxies.push(p.clone());
        }
    }
    m.insert(s("proxies"), Value::Sequence(proxies));

    let mut groups = seq(m, "proxy-groups");
    let names: Vec<&str> = plan.groups.iter().map(|g| g.0.as_str()).collect();
    groups.retain(|g| !g.get("name").and_then(|n| n.as_str()).is_some_and(|n| names.contains(&n)));
    for (name, members) in plan.groups.iter().rev() {
        let mut g = Mapping::new();
        g.insert(s("name"), s(name));
        g.insert(s("type"), s("select"));
        let mut ms: Vec<Value> = members.iter().map(|x| s(x)).collect();
        if ms.is_empty() {
            ms.push(s("DIRECT"));
        }
        g.insert(s("proxies"), Value::Sequence(ms));
        groups.insert(0, Value::Mapping(g));
    }
    m.insert(s("proxy-groups"), Value::Sequence(groups));

    let mut rules = seq(m, "rules");
    if let Some(t) = &plan.match_target {
        for r in rules.iter_mut() {
            if r.as_str().is_some_and(|x| x.trim_start().to_ascii_uppercase().starts_with("MATCH,")) {
                *r = s(&format!("MATCH,{t}"));
            }
        }
    }
    let mut front: Vec<Value> = plan.rules_front.iter().map(|x| s(x)).collect();
    front.append(&mut rules);
    m.insert(s("rules"), Value::Sequence(front));
}

/// 订阅正文（已经过 normalize_body）+ Zephyr 设置 → mihomo 运行时 YAML。
pub fn build_runtime_config(subscription_yaml: &str, o: &RuntimeOptions) -> Result<String, MobileError> {
    build_runtime_config_with(subscription_yaml, o, &ScenePlan::default())
}

pub fn build_runtime_config_with(subscription_yaml: &str, o: &RuntimeOptions, plan: &ScenePlan) -> Result<String, MobileError> {
    let mut v: Value = serde_yaml::from_str(subscription_yaml).map_err(|e| MobileError::SubscriptionInvalid(e.to_string()))?;
    if !v.is_mapping() {
        return Err(MobileError::SubscriptionInvalid("配置根不是映射".into()));
    }
    merge_yaml(&mut v, &overlay(o), 0).map_err(MobileError::Invalid)?;
    // 桌面端安全钉死：不开 TCP 控制端口、去掉 secret 以外的一切控制面入口
    restore_security_settings(&mut v, &SecuritySettings { external_controller: None, secret: None, tun_enabled: o.tun.file_descriptor.is_some() });
    let Value::Mapping(m) = &mut v else { unreachable!() };
    // 覆盖层里的 Null 是"删除"语义；目标原本不存在时会被原样插入，这里清掉
    for k in ["dns", "tun"] {
        if let Some(Value::Mapping(sub)) = m.get_mut(s(k)) {
            sub.retain(|_, x| !x.is_null());
        }
    }
    m.retain(|_, x| !x.is_null());
    m.remove(s("external-controller"));
    m.remove(s("secret"));
    // 移动端唯一控制面：私有目录 unix socket（文件权限即访问控制）
    m.insert(s("external-controller-unix"), s(&o.controller_socket));
    if !m.contains_key(s("rules")) {
        m.insert(s("rules"), Value::Sequence(vec![s("MATCH,DIRECT")]));
    }
    apply_plan(m, plan);
    serde_yaml::to_string(&v).map_err(|e| MobileError::Invalid(e.to_string()))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn opts(fd: Option<i32>) -> RuntimeOptions {
        RuntimeOptions {
            dns: DnsConfig { fake_ip: true, nameservers: vec!["https://dns.alidns.com/dns-query".into()], fallback: vec![], ipv6: false },
            tun: TunConfig { stack: TunStackKind::Gvisor, mtu: 9000, ipv6: false, strict_route: true, file_descriptor: fd },
            mode: ProxyMode::Rule,
            controller_socket: "/data/zm.sock".into(),
            find_process: false,
            log_level: "warning".into(),
        }
    }

    const SUB: &str = "mixed-port: 7890\nallow-lan: true\nexternal-controller: 0.0.0.0:9090\nsecret: leaked\nexternal-ui: ui\nexternal-controller-unix: /tmp/evil.sock\ndns:\n  enable: true\n  fallback: [8.8.8.8]\n  nameserver-policy: {'+.corp': 10.0.0.1}\nproxies:\n  - {name: a, server: a.example, port: 443, type: trojan, password: p}\nproxy-groups:\n  - {name: AI, type: select, proxies: [a]}\nrules:\n  - DOMAIN-SUFFIX,claude.ai,AI\n  - MATCH,DIRECT\n";

    #[test]
    fn pins_control_plane_and_applies_settings() {
        let out = build_runtime_config(SUB, &opts(Some(42))).unwrap();
        let v: Value = serde_yaml::from_str(&out).unwrap();
        assert_eq!(v["external-controller-unix"].as_str(), Some("/data/zm.sock"));
        for k in ["external-controller", "secret", "external-ui", "mixed-port"] {
            assert!(v.get(k).is_none(), "{k} 应被移除：{out}");
        }
        assert_eq!(v["allow-lan"].as_bool(), Some(false));
        assert_eq!(v["tun"]["file-descriptor"].as_i64(), Some(42));
        assert_eq!(v["tun"]["stack"].as_str(), Some("gvisor"));
        assert_eq!(v["tun"]["auto-route"].as_bool(), Some(false));
        let hj: Vec<&str> = v["tun"]["dns-hijack"].as_sequence().unwrap().iter().filter_map(|x| x.as_str()).collect();
        assert_eq!(hj, vec!["any:53", "tcp://any:53"]);
        assert_eq!(v["dns"]["enhanced-mode"].as_str(), Some("fake-ip"));
        assert!(v["dns"].get("fallback").is_none(), "空 fallback 删除订阅自带的");
        assert!(v["dns"].get("nameserver-policy").is_some(), "订阅里其它 DNS 设置保留");
        assert_eq!(v["rules"][0].as_str(), Some("DOMAIN-SUFFIX,claude.ai,AI"));
        assert_eq!(v["find-process-mode"].as_str(), Some("off"));
    }

    /// 写出一份真实形状的配置，供 mihomo-mobile 的 Go 测试加载（ZM_RUNTIME_CONFIG）。
    #[test]
    fn emit_for_mihomo_smoke() {
        let Ok(p) = std::env::var("ZM_RUNTIME_CONFIG") else { return };
        let body = crate::subs::normalize_body(SUB).unwrap();
        std::fs::write(p, build_runtime_config(&body, &opts(None)).unwrap()).unwrap();
    }

    #[test]
    fn no_fd_means_tun_off() {
        let v: Value = serde_yaml::from_str(&build_runtime_config("proxies: []\n", &opts(None)).unwrap()).unwrap();
        assert_eq!(v["tun"]["enable"].as_bool(), Some(false));
        assert!(!build_runtime_config("proxies: []\n", &opts(None)).unwrap().contains("null"));
        assert_eq!(v["rules"][0].as_str(), Some("MATCH,DIRECT"));
    }
}
