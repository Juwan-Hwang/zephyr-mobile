//! 节点详情与按需延迟测试（契约 §5 node / testLatency / nodeIndex.testedCount）。
//!
//! 节点库上千万条，运行配置里只放场景引用的少数节点，所以延迟测试不能走 mihomo REST：
//! 核心按 id 从订阅正文取出代理定义（name 改成 id 的十六进制），平台交给 `zm_url_test` 临时建出站测，
//! 再把结果 JSON 交回 `recordUrlTest` 入延迟缓存。

use crate::engine::MobileCore;
use crate::error::MobileError;
use crate::latency::LatencySample;
use crate::nodes::NodeRow;
use rustc_hash::{FxHashMap, FxHashSet};
use serde_yaml::Value;
use std::collections::HashMap;

/// 单批上限，与 mihomo-mobile `maxURLTestBatch` 一致。
pub const URL_TEST_BATCH: usize = 512;

#[derive(Debug, Clone, PartialEq, uniffi::Record)]
pub struct NodeDetail {
    pub row: NodeRow,
    /// 已脱敏（"a1***.example.com" / "198.51.*.*"）
    pub server: String,
    pub port: i32,
    pub subscription: String,
    /// 只含非敏感字段：network / tls / sni / udp / flow / plugin；绝不含密码、uuid、私钥。
    pub extra: HashMap<String, String>,
    /// 最近一次测速（不限新鲜度，-1 = 超时）；从未测过为 None。
    pub latency_ms: Option<i32>,
    pub latency_at: Option<i64>,
}

/// 服务器地址脱敏：IPv4 留前两段；IPv6 留前两组；域名留首段前 2 个字符与最后两段。
pub fn mask_server(s: &str) -> String {
    if let Ok(ip) = s.parse::<std::net::IpAddr>() {
        return match ip {
            std::net::IpAddr::V4(v) => {
                let o = v.octets();
                format!("{}.{}.*.*", o[0], o[1])
            }
            std::net::IpAddr::V6(v) => {
                let g = v.segments();
                format!("{:x}:{:x}:*", g[0], g[1])
            }
        };
    }
    let parts: Vec<&str> = s.split('.').collect();
    if parts.len() < 2 {
        return format!("{}***", s.chars().take(2).collect::<String>());
    }
    let head: String = parts[0].chars().take(2).collect();
    let tail = if parts.len() >= 3 { parts[parts.len() - 2..].join(".") } else { parts[parts.len() - 1].to_string() };
    format!("{head}***.{tail}")
}

const SAFE_EXTRA: &[&str] = &["network", "tls", "sni", "servername", "udp", "flow", "plugin", "cipher", "alpn", "client-fingerprint"];

fn scalar(v: &Value) -> Option<String> {
    match v {
        Value::String(s) => Some(s.clone()),
        Value::Bool(b) => Some(b.to_string()),
        Value::Number(n) => Some(n.to_string()),
        Value::Sequence(xs) => Some(xs.iter().filter_map(scalar).collect::<Vec<_>>().join(",")),
        _ => None,
    }
}

#[derive(serde::Deserialize)]
struct UrlTestOut {
    #[serde(default)]
    results: Vec<UrlTestItem>,
    #[serde(default)]
    error: Option<String>,
}
#[derive(serde::Deserialize)]
struct UrlTestItem {
    name: String,
    ms: i32,
}

type DefsById = (FxHashMap<u64, NodeRow>, FxHashMap<u64, Value>);

impl MobileCore {
    /// id → 代理定义（按订阅分组，每个正文只解析一次）。
    fn proxy_defs_by_id(&self, ids: &[u64]) -> Result<DefsById, MobileError> {
        let rows = self.rows_by_id_pub(ids)?;
        let mut by_slot: FxHashMap<u16, FxHashSet<u64>> = Default::default();
        for r in rows.values() {
            by_slot.entry(r.subscription).or_default().insert(r.id);
        }
        let mut defs = FxHashMap::default();
        let subs = self.subs.lock();
        for (slot, want) in by_slot {
            let Some(body) = subs.body(slot) else { continue };
            for (fp, def) in crate::subs::proxy_defs(&body, &want) {
                defs.insert(fp, def);
            }
        }
        Ok((rows, defs))
    }
}

/// 场景 sheet 漏斗（原型"检测自 2 个订阅中的 512 个节点 → 延迟低于 300 ms → …"），契约 §15.c。
/// 只给核心真实知道的级；"可访问 GPT"等按服务的级需要逐节点探测，核心没有，平台不显示。
#[derive(Debug, Clone, PartialEq, uniffi::Record)]
pub struct NodeFunnel {
    /// 订阅数
    pub source_count: u32,
    /// 节点库总数
    pub pool_size: u64,
    /// max_age 内测过（含超时）且仍在库中的节点数
    pub tested: u64,
    /// 其中测速成功（ms ≥ 0）
    pub reachable: u64,
    /// 其中 ms < threshold_ms
    pub under_threshold: u64,
    pub threshold_ms: i32,
}

#[derive(Debug, Clone, PartialEq, uniffi::Record)]
pub struct TcpTarget {
    pub id: u64,
    pub host: String,
    pub port: u16,
}

#[uniffi::export]
impl MobileCore {
    pub fn node_detail(&self, id: u64) -> Result<NodeDetail, MobileError> {
        let (mut rows, mut defs) = self.proxy_defs_by_id(&[id])?;
        let row = rows.remove(&id).ok_or_else(|| MobileError::NotFound(format!("node {id:x}")))?;
        let subscription = self.subs.lock().entries.iter().find(|e| e.slot == row.subscription).map(|e| e.meta.name.clone()).unwrap_or_default();
        let (mut server, mut port, mut extra) = (String::new(), 0, HashMap::new());
        if let Some(Value::Mapping(m)) = defs.remove(&id) {
            server = m.get("server").and_then(scalar).map(|s| mask_server(&s)).unwrap_or_default();
            port = m.get("port").and_then(|p| p.as_i64().or_else(|| p.as_str().and_then(|s| s.parse().ok()))).unwrap_or(0) as i32;
            for k in SAFE_EXTRA {
                if let Some(v) = m.get(*k).and_then(scalar) {
                    extra.insert((*k).to_string(), v);
                }
            }
        }
        let last = self.latency.lock().get(id, 0, 0);
        Ok(NodeDetail { row, server, port, subscription, extra, latency_ms: last.map(|x| x.0), latency_at: last.map(|x| x.1) })
    }

    /// 给 `zm_url_test` 的一批代理定义（JSON 数组，name = id 十六进制）。超过 512 个报错；找不到定义的 id 跳过。
    pub fn latency_test_batch(&self, ids: Vec<u64>) -> Result<String, MobileError> {
        if ids.len() > URL_TEST_BATCH {
            return Err(MobileError::Invalid(format!("batch > {URL_TEST_BATCH}")));
        }
        let (_, defs) = self.proxy_defs_by_id(&ids)?;
        let mut out = Vec::with_capacity(defs.len());
        for id in ids {
            if let Some(Value::Mapping(m)) = defs.get(&id) {
                let mut m = m.clone();
                m.insert("name".into(), format!("{id:x}").into());
                let j = serde_json::to_value(Value::Mapping(m)).map_err(|e| MobileError::Invalid(e.to_string()))?;
                out.push(j);
            }
        }
        serde_json::to_string(&out).map_err(|e| MobileError::Invalid(e.to_string()))
    }

    /// `zm_url_test` 的返回 JSON 入延迟缓存，返回记录下的样本（供 latencyUpdates 推送）。
    pub fn record_url_test(&self, result_json: String, now_millis: i64) -> Result<Vec<LatencySample>, MobileError> {
        let out: UrlTestOut = serde_json::from_str(&result_json).map_err(|e| MobileError::Invalid(format!("url test: {e}")))?;
        if let Some(e) = out.error {
            return Err(MobileError::Invalid(format!("url test: {e}")));
        }
        let samples: Vec<LatencySample> = out
            .results
            .into_iter()
            .filter_map(|r| u64::from_str_radix(&r.name, 16).ok().map(|id| LatencySample { id, ms: if r.ms > 0 { r.ms } else { -1 }, at: now_millis }))
            .collect();
        self.record_latencies(samples.clone())?;
        Ok(samples)
    }

    /// 隧道未连接时的测速目标（契约 §14.u）：平台直接测到 server:port 的 TCP 握手时间，结果用 recordLatencies 写回。
    /// 只在本进程内使用，不展示，server 不脱敏。基于 UDP 的协议（hysteria/hysteria2/hy2/tuic/wireguard/wg）无法 TCP 握手，跳过。
    /// 超过 512 个报错；找不到定义的 id 跳过。
    pub fn tcp_ping_targets(&self, ids: Vec<u64>) -> Result<Vec<TcpTarget>, MobileError> {
        if ids.len() > URL_TEST_BATCH {
            return Err(MobileError::Invalid(format!("batch > {URL_TEST_BATCH}")));
        }
        let (_, defs) = self.proxy_defs_by_id(&ids)?;
        Ok(ids
            .into_iter()
            .filter_map(|id| {
                let Some(Value::Mapping(m)) = defs.get(&id) else { return None };
                let ty = m.get("type").and_then(|t| t.as_str()).unwrap_or("").to_ascii_lowercase();
                if matches!(ty.as_str(), "hysteria" | "hysteria2" | "hy2" | "tuic" | "wireguard" | "wg") {
                    return None;
                }
                let host = m.get("server").and_then(scalar)?;
                let port = m.get("port").and_then(|p| p.as_i64().or_else(|| p.as_str().and_then(|s| s.parse().ok())))?;
                (!host.is_empty() && (1..=65535).contains(&port)).then_some(TcpTarget { id, host, port: port as u16 })
            })
            .collect())
    }

    /// 有新鲜测速结果（max_age 内，含超时）的节点数；max_age ≤ 0 不限。
    pub fn tested_count(&self, now_millis: i64, max_age_millis: i64) -> u64 {
        let c = self.latency.lock();
        c.map.values().filter(|v| v.last().is_some_and(|&(_, at)| max_age_millis <= 0 || now_millis - at <= max_age_millis)).count() as u64
    }

    /// 漏斗计数（§15.c）。只看每个节点最近一次样本；max_age ≤ 0 不限新鲜度；threshold_ms ≤ 0 按 300。
    pub fn node_funnel(&self, now_millis: i64, max_age_millis: i64, threshold_ms: i32) -> Result<NodeFunnel, MobileError> {
        let threshold_ms = if threshold_ms <= 0 { 300 } else { threshold_ms };
        let source_count = self.subs.lock().entries.len() as u32;
        let st = self.store()?;
        let fresh: Vec<(u64, i32)> = {
            let c = self.latency.lock();
            c.map
                .iter()
                .filter_map(|(&id, v)| v.last().filter(|&&(_, at)| max_age_millis <= 0 || now_millis - at <= max_age_millis).map(|&(ms, _)| (id, ms)))
                .collect()
        };
        // 订阅删除后缓存里可能还有旧指纹：只数仍在库中的
        let ids: Vec<u64> = fresh.iter().map(|x| x.0).collect();
        let live: FxHashSet<u64> = self.positions(&st, &ids).into_keys().collect();
        let mut f = NodeFunnel { source_count, pool_size: st.total(), tested: 0, reachable: 0, under_threshold: 0, threshold_ms };
        for (_, ms) in fresh.into_iter().filter(|x| live.contains(&x.0)) {
            f.tested += 1;
            if ms >= 0 {
                f.reachable += 1;
                if ms < threshold_ms {
                    f.under_threshold += 1;
                }
            }
        }
        Ok(f)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn masks_servers() {
        assert_eq!(mask_server("198.51.100.7"), "198.51.*.*");
        assert_eq!(mask_server("a1.node.example.com"), "a1***.example.com");
        assert_eq!(mask_server("2001:db8::1"), "2001:db8:*");
        assert_eq!(mask_server("localhost"), "lo***");
    }

    #[test]
    fn tcp_targets() {
        let (_d, core, _sub, rows) = crate::scene_api::tests::setup();
        let ids: Vec<u64> = rows.iter().map(|r| r.id).collect();
        let t = core.tcp_ping_targets(ids.clone()).unwrap();
        assert!(!t.is_empty());
        assert!(t.iter().all(|x| !x.host.contains("***") && x.port > 0));
        assert!(core.tcp_ping_targets(vec![0; 513]).is_err());
    }

    #[test]
    fn funnel_counts() {
        let (_d, core, _sub, rows) = crate::scene_api::tests::setup();
        let f = core.node_funnel(2000, 0, 75).unwrap();
        assert_eq!((f.source_count, f.pool_size, f.tested, f.reachable, f.under_threshold, f.threshold_ms), (2, 5, 4, 4, 3, 75));
        // 超时计入 tested 不计 reachable；不在库中的旧指纹不计
        core.record_latencies(vec![LatencySample { id: rows[0].id, ms: -1, at: 3000 }, LatencySample { id: 0xdead_beef, ms: 10, at: 3000 }]).unwrap();
        let f = core.node_funnel(3000, 0, 0).unwrap();
        assert_eq!((f.tested, f.reachable, f.under_threshold, f.threshold_ms), (4, 3, 3, 300));
        // 新鲜度：只看 1.5 s 内的 → 只剩刚记的那条超时
        let f = core.node_funnel(3000, 1500, 300).unwrap();
        assert_eq!((f.tested, f.reachable), (1, 0));
    }

    #[test]
    fn detail_batch_and_record() {
        let (_d, core, _sub, rows) = crate::scene_api::tests::setup();
        let id = rows[0].id;
        let d = core.node_detail(id).unwrap();
        assert_eq!(d.row.id, id);
        assert_eq!(d.port, if d.server.starts_with("b0") { 8443 } else { 443 });
        assert!(d.server.contains("***"), "{}", d.server);
        assert!(!d.subscription.is_empty());
        assert_eq!(d.latency_at, Some(1000), "setup 记录过测速");
        assert!(!format!("{d:?}").contains("password") && !format!("{d:?}").contains("00000000-0000"), "不泄露凭据");

        let ids: Vec<u64> = rows.iter().map(|r| r.id).collect();
        let batch = core.latency_test_batch(ids.clone()).unwrap();
        let v: Vec<serde_json::Value> = serde_json::from_str(&batch).unwrap();
        assert_eq!(v.len(), 4);
        assert_eq!(v[0]["name"].as_str().unwrap(), format!("{:x}", ids[0]));
        assert!(core.latency_test_batch(vec![1; URL_TEST_BATCH + 1]).is_err());

        let before = core.tested_count(1000, 0);
        let res = format!(r#"{{"results":[{{"name":"{:x}","ms":42}},{{"name":"{:x}","ms":-1}},{{"name":"zz","ms":5}}]}}"#, ids[0], ids[1]);
        let s = core.record_url_test(res, 5000).unwrap();
        assert_eq!(s.len(), 2);
        assert_eq!((s[0].ms, s[1].ms), (42, -1));
        assert_eq!(core.tested_count(5000, 0), before);
        assert_eq!(core.tested_count(5000, 1000), 2, "只有新样本在 1 s 内");
        assert!(core.record_url_test(r#"{"error":"boom"}"#.into(), 1).is_err());
    }
}
