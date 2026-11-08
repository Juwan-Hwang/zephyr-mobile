//! MobileCore 的场景 / 覆写 / 设置与存储接口（contract §3、§9、§13）。

use crate::engine::{MobileCore, RankedNode};
use crate::error::MobileError;
use crate::nodes::NodeRow;
use crate::runtime_config::ScenePlan;
use crate::scenes::{self, HostOverride, SceneKind, SceneRec, SceneSource, TraceTarget};
use rustc_hash::FxHashSet;

/// 场景出口候选：只要 24 h 内测过的。
const FRESH_MS: i64 = 24 * 3_600_000;
/// 组内热备数：切到这些节点不需要重载 mihomo。
const STANDBY: usize = 8;

#[derive(Debug, Clone, PartialEq, uniffi::Record)]
pub struct SceneExceptionView {
    pub app_id: String,
    pub app: String,
    pub node: Option<NodeRow>,
}

#[derive(Debug, Clone, PartialEq, uniffi::Record)]
pub struct Scene {
    pub id: String,
    pub kind: SceneKind,
    pub name: String,
    /// "9 个可用"：所选地区 24 h 内测速成功的节点数（≤ 50）
    pub available: i32,
    pub selected: Option<NodeRow>,
    pub selected_latency_ms: Option<i32>,
    pub exit_ip: Option<String>,
    pub exit_region: Option<String>,
    pub source: SceneSource,
    pub tested_at: Option<i64>,
    pub note: Option<String>,
    pub exceptions: Vec<SceneExceptionView>,
    /// 按服务健康（原型："Claude 不可用 / GPT、Gemini 正常"）；未探测过的服务不出现。
    pub services: Vec<ServiceHealth>,
    /// mihomo 中的组名（MihomoClient.selectInGroup 用）
    pub group: String,
}

#[derive(Debug, Clone, PartialEq, uniffi::Record)]
pub struct ServiceHealth {
    pub app_id: String,
    pub name: String,
    pub ok: bool,
    pub checked_at: i64,
}

/// 平台对场景内服务做健康探测的目标：经 VPN 访问 url，规则会把它路由到该服务实际使用的出口（含应用例外）。
#[derive(Debug, Clone, PartialEq, uniffi::Record)]
pub struct ProbeTarget {
    pub app_id: String,
    pub name: String,
    pub url: String,
}

#[derive(Debug, Clone, PartialEq, uniffi::Record)]
pub struct ExitChange {
    pub scene_id: Option<String>,
    pub from_region: Option<String>,
    pub from_ip: Option<String>,
    pub to_region: String,
    /// 新出口 IP 要连上后才知道
    pub to_ip: Option<String>,
    pub affected_apps: Vec<String>,
    pub unchanged_apps: Vec<String>,
}

/// applySceneChange 的结果：平台据此决定热切换还是重载。
#[derive(Debug, Clone, PartialEq, uniffi::Record)]
pub struct SceneApply {
    /// true：新节点不在当前组里，需 runtimeConfig + zm_reload
    pub needs_reload: bool,
    pub group: String,
    /// mihomo 成员名；needs_reload = false 时直接 selectInGroup(group, member)
    pub member: String,
    /// 撤销用：再 apply 这个节点
    pub previous: Option<u64>,
}

#[derive(Debug, Clone, PartialEq, uniffi::Record)]
pub struct StorageInfo {
    pub nodes_bytes: i64,
    pub rules_bytes: i64,
    pub subscriptions_bytes: i64,
    pub cache_bytes: i64,
}

/// mihomo 里的成员名：原名 + 指纹短码，保证跨订阅同名节点不冲突且确定。
pub fn member_name(row: &NodeRow) -> String {
    format!("{} ·{:04x}", row.name, row.id >> 48)
}

fn dir_bytes(p: &std::path::Path) -> i64 {
    std::fs::read_dir(p)
        .map(|rd| {
            rd.filter_map(|e| e.ok())
                .map(|e| match e.metadata() {
                    Ok(m) if m.is_dir() => dir_bytes(&e.path()),
                    Ok(m) => m.len() as i64,
                    Err(_) => 0,
                })
                .sum()
        })
        .unwrap_or(0)
}

impl MobileCore {
    fn rows_by_id(&self, ids: &[u64]) -> Result<rustc_hash::FxHashMap<u64, NodeRow>, MobileError> {
        let st = self.store()?;
        let pos = self.positions(&st, ids);
        Ok(pos.into_iter().map(|(id, p)| (id, st.row(p))).collect())
    }

    pub(crate) fn rows_by_id_pub(&self, ids: &[u64]) -> Result<rustc_hash::FxHashMap<u64, NodeRow>, MobileError> {
        self.rows_by_id(ids)
    }

    fn row_by_id(&self, id: u64) -> Result<NodeRow, MobileError> {
        self.rows_by_id(&[id])?.remove(&id).ok_or_else(|| MobileError::NotFound(format!("node {id:x}")))
    }

    fn view(&self, s: &SceneRec, rows: &rustc_hash::FxHashMap<u64, NodeRow>, now: i64) -> Scene {
        let selected = s.selected.and_then(|id| rows.get(&id).cloned());
        let available = selected
            .as_ref()
            .and_then(|r| self.fastest_nodes(r.region.clone(), 50, now, FRESH_MS).ok())
            .map(|v| v.iter().filter(|x| x.latency_ms >= 0).count() as i32)
            .unwrap_or(0);
        let lat = s.selected.and_then(|id| self.latency.lock().get(id, now, 0).map(|x| x.0));
        Scene {
            id: s.id.clone(),
            kind: s.kind,
            name: s.name.clone(),
            available,
            selected,
            selected_latency_ms: lat,
            exit_ip: s.exit_ip.clone(),
            exit_region: s.exit_region.clone(),
            source: s.source,
            tested_at: s.tested_at,
            note: s.note.clone(),
            exceptions: s
                .exceptions
                .iter()
                .map(|(a, n)| SceneExceptionView { app_id: a.clone(), app: scenes::app(a).map_or(a.clone(), |x| x.name.to_string()), node: rows.get(n).cloned() })
                .collect(),
            group: scenes::group_name(s),
            services: s
                .services
                .iter()
                .map(|r| ServiceHealth { app_id: r.app_id.clone(), name: scenes::app(&r.app_id).map_or(r.app_id.clone(), |a| a.name.to_string()), ok: r.ok, checked_at: r.checked_at })
                .collect(),
        }
    }

    /// 由场景、例外、覆写算出注入计划（runtime_config 内部用）。
    pub(crate) fn scene_plan(&self) -> Result<ScenePlan, MobileError> {
        // 先复制再放锁：下面要取 subs 锁，而订阅更新路径是 subs → scenes，避免锁序反转
        let sc = self.scenes.lock().clone();
        let ids = sc.referenced_nodes();
        let mut plan = ScenePlan::default();
        let rows = if ids.is_empty() { Default::default() } else { self.rows_by_id(&ids).unwrap_or_default() };
        // 代理定义：按订阅分组，每个正文只解析一次
        let mut by_slot: rustc_hash::FxHashMap<u16, FxHashSet<u64>> = Default::default();
        for r in rows.values() {
            by_slot.entry(r.subscription).or_default().insert(r.id);
        }
        let mut defined = FxHashSet::default();
        {
            let subs = self.subs.lock();
            for (slot, want) in by_slot {
                let Some(body) = subs.body(slot) else { continue };
                for (fp, mut def) in crate::subs::proxy_defs(&body, &want) {
                    if let (Some(row), serde_yaml::Value::Mapping(m)) = (rows.get(&fp), &mut def) {
                        m.insert("name".into(), member_name(row).into());
                        plan.proxies.push(def);
                        defined.insert(fp);
                    }
                }
            }
        }
        let member = |id: &u64| defined.contains(id).then(|| member_name(&rows[id]));
        // 1. 覆写
        for o in &sc.overrides {
            let target = match o.target {
                TraceTarget::Direct => Some("DIRECT".to_string()),
                TraceTarget::Scene => o.scene_id.as_deref().and_then(|id| sc.get(id).ok()).map(scenes::group_name),
                TraceTarget::Unchanged => None,
            };
            if let Some(t) = target {
                plan.rules_front.push(format!("DOMAIN-SUFFIX,{},{t}", o.host));
            }
        }
        for s in &sc.scenes {
            // 2. 例外
            for (app_id, node) in &s.exceptions {
                let g = scenes::exception_group_name(s, app_id);
                plan.groups.push((g.clone(), member(node).into_iter().collect()));
                if let Some(a) = scenes::app(app_id) {
                    plan.rules_front.extend(a.domains.iter().map(|d| format!("DOMAIN-SUFFIX,{d},{g}")));
                }
            }
            // 场景组：当前节点在前，热备在后
            let mut members: Vec<String> = s.selected.iter().chain(s.standby.iter()).filter_map(member).collect();
            members.dedup();
            let g = scenes::group_name(s);
            let has_node = !members.is_empty();
            plan.groups.push((g.clone(), members));
            // 3. 场景应用（没选节点的场景不接管流量，留给订阅规则）
            if has_node {
                match s.kind {
                    SceneKind::Ai | SceneKind::Video => {
                        let ex: Vec<&str> = s.exceptions.iter().map(|e| e.0.as_str()).collect();
                        for a in scenes::APPS.iter().filter(|a| a.kind == s.kind && !ex.contains(&a.id)) {
                            plan.rules_front.extend(a.domains.iter().map(|d| format!("DOMAIN-SUFFIX,{d},{g}")));
                        }
                    }
                    SceneKind::Other => plan.match_target = Some(g),
                    SceneKind::Custom => {}
                }
            }
        }
        Ok(plan)
    }
}

impl MobileCore {
    /// 规则页第 1 层"Zephyr 覆写"与真实路由保持一致：由覆写、例外、场景应用域名生成，
    /// 写入 rules/000.zr（索引 0 由核心保留）并热加载。策略写场景 id（"ai"）或 DIRECT。
    pub(crate) fn sync_override_layer(&self) -> Result<(), MobileError> {
        let sc = self.scenes.lock().clone();
        let mut text = String::new();
        for o in &sc.overrides {
            let p = match o.target {
                TraceTarget::Direct => "DIRECT".to_string(),
                TraceTarget::Scene => match o.scene_id.clone() { Some(x) => x, None => continue },
                TraceTarget::Unchanged => continue,
            };
            text += &format!("DOMAIN-SUFFIX,{},{p}\n", o.host);
        }
        for s in sc.scenes.iter().filter(|s| s.selected.is_some()) {
            let ex: Vec<&str> = s.exceptions.iter().map(|e| e.0.as_str()).collect();
            for a in scenes::APPS.iter().filter(|a| a.kind == s.kind) {
                if s.kind == SceneKind::Ai || s.kind == SceneKind::Video || ex.contains(&a.id) {
                    for d in a.domains {
                        text += &format!("DOMAIN-SUFFIX,{d},{}\n", s.id);
                    }
                }
            }
        }
        self.compile_rule_layer(0, "Zephyr 覆写".into(), crate::rules::LayerKind::Override, "在订阅之上".into(), "DIRECT".into(), text)?;
        let fin = self.rules.read().final_policy.clone();
        self.load_rules(fin)?;
        Ok(())
    }
}

#[uniffi::export]
impl MobileCore {
    pub fn scenes(&self, now_millis: i64) -> Result<Vec<Scene>, MobileError> {
        let recs = self.scenes.lock().scenes.clone();
        let ids: Vec<u64> = recs.iter().flat_map(|s| s.selected.into_iter().chain(s.exceptions.iter().map(|e| e.1))).collect();
        let rows = if ids.is_empty() || self.store().is_err() { Default::default() } else { self.rows_by_id(&ids)? };
        Ok(recs.iter().map(|s| self.view(s, &rows, now_millis)).collect())
    }

    /// 左右滑动切地区；region 为空时用当前节点所在地区。按 smart 分数排序，最多 50。
    pub fn scene_candidates(&self, scene_id: String, region: Option<String>, now_millis: i64) -> Result<Vec<RankedNode>, MobileError> {
        let sel = self.scenes.lock().get(&scene_id)?.selected;
        let region = match region {
            Some(r) => r,
            None => match sel {
                Some(id) => self.row_by_id(id)?.region,
                None => return Ok(vec![]),
            },
        };
        self.fastest_nodes(region, 50, now_millis, FRESH_MS)
    }

    pub fn preview_scene_change(&self, scene_id: String, node_id: u64) -> Result<ExitChange, MobileError> {
        let to = self.row_by_id(node_id)?;
        let sc = self.scenes.lock().clone();
        let s = sc.get(&scene_id)?;
        let from_region = s.exit_region.clone().or_else(|| s.selected.and_then(|id| self.row_by_id(id).ok()).map(|r| r.region));
        let (affected, unchanged) = sc.apps_split(s);
        Ok(ExitChange { scene_id: Some(scene_id), from_region, from_ip: s.exit_ip.clone(), to_region: to.region, to_ip: None, affected_apps: affected, unchanged_apps: unchanged })
    }

    pub fn apply_scene_change(&self, scene_id: String, node_id: u64, now_millis: i64) -> Result<SceneApply, MobileError> {
        let to = self.row_by_id(node_id)?;
        let standby: Vec<u64> = self.fastest_nodes(to.region.clone(), STANDBY as u32 + 1, now_millis, FRESH_MS)?.into_iter().map(|r| r.row.id).filter(|&id| id != node_id).take(STANDBY).collect();
        let mut sc = self.scenes.lock();
        let s = sc.get_mut(&scene_id)?;
        let hot = s.selected == Some(node_id) || s.standby.contains(&node_id);
        let previous = s.selected;
        s.selected = Some(node_id);
        if !hot {
            // 热切换时保持组成员不变（否则组和运行中的 mihomo 不一致）；重载时换成新地区的热备
            s.standby = standby;
        } else if let Some(p) = previous.filter(|&p| p != node_id) {
            if !s.standby.contains(&p) {
                s.standby.push(p);
            }
        }
        s.source = SceneSource::Manual;
        s.exit_ip = None;
        s.exit_region = None;
        let group = scenes::group_name(s);
        sc.save()?;
        drop(sc);
        if previous.is_none() {
            self.sync_override_layer()?;
        }
        Ok(SceneApply { needs_reload: !hot, group, member: member_name(&to), previous })
    }

    /// 全局模式换出口的预览（"所有流量均经由新加坡 02。场景已暂停。"）：影响全部应用。
    pub fn preview_global_change(&self, node_id: u64) -> Result<ExitChange, MobileError> {
        let to = self.row_by_id(node_id)?;
        let from = self.scenes.lock().global;
        let from_region = from.and_then(|id| self.row_by_id(id).ok()).map(|r| r.region);
        let affected = scenes::APPS.iter().map(|a| a.name.to_string()).collect();
        Ok(ExitChange { scene_id: None, from_region, from_ip: None, to_region: to.region, to_ip: None, affected_apps: affected, unchanged_apps: vec![] })
    }

    /// 全局模式出口。返回的 group 恒为 mihomo 内置 "GLOBAL"：平台在需要时先重载（节点此前不在配置里），
    /// 然后**总是** selectInGroup("GLOBAL", member)。
    pub fn set_global_node(&self, node_id: u64) -> Result<SceneApply, MobileError> {
        let to = self.row_by_id(node_id)?;
        let mut sc = self.scenes.lock();
        let previous = sc.global;
        let already = sc.referenced_nodes().contains(&node_id);
        sc.global = Some(node_id);
        sc.save()?;
        Ok(SceneApply { needs_reload: !already, group: "GLOBAL".into(), member: member_name(&to), previous })
    }

    pub fn global_node(&self) -> Option<u64> {
        self.scenes.lock().global
    }

    /// 平台测得出口后回填（"198.51.100.7 · 美国"）。
    pub fn report_scene_exit(&self, scene_id: String, ip: String, region: Option<String>, tested_at: i64) -> Result<(), MobileError> {
        let mut sc = self.scenes.lock();
        let s = sc.get_mut(&scene_id)?;
        s.exit_ip = Some(ip);
        s.exit_region = region;
        s.tested_at = Some(tested_at);
        sc.save()
    }

    /// 场景内需要探测健康的服务（按内置应用目录，有 probe 地址的）。
    pub fn scene_probe_targets(&self, scene_id: String) -> Result<Vec<ProbeTarget>, MobileError> {
        let kind = self.scenes.lock().get(&scene_id)?.kind;
        Ok(scenes::APPS
            .iter()
            .filter(|a| a.kind == kind)
            .filter_map(|a| a.probe.map(|u| ProbeTarget { app_id: a.id.into(), name: a.name.into(), url: u.into() }))
            .collect())
    }

    /// 平台探测某服务后上报；只记录，不触发任何切换（AI 出口仅用户确认后更改，§14.y）。
    pub fn report_scene_service(&self, scene_id: String, app_id: String, ok: bool, now_millis: i64) -> Result<(), MobileError> {
        if scenes::app(&app_id).is_none() {
            return Err(MobileError::Invalid(format!("unknown app {app_id}")));
        }
        let mut sc = self.scenes.lock();
        let s = sc.get_mut(&scene_id)?;
        s.services.retain(|r| r.app_id != app_id);
        s.services.push(scenes::ServiceRec { app_id, ok, checked_at: now_millis });
        let order = |id: &str| scenes::APPS.iter().position(|a| a.id == id).unwrap_or(usize::MAX);
        s.services.sort_by_key(|r| order(&r.app_id));
        sc.save()
    }

    /// 测场景出口用的地址（Cloudflare trace，返回 ip= / loc=）。请求按域名走规则，所以选一个属于该场景、
    /// 且没被设成例外的服务域名；视频与自定义场景没有可用的 trace 域名，返回 None。
    pub fn scene_exit_probe(&self, scene_id: String) -> Result<Option<String>, MobileError> {
        let sc = self.scenes.lock();
        let s = sc.get(&scene_id)?;
        let excepted = |id: &str| s.exceptions.iter().any(|e| e.0 == id);
        Ok(match s.kind {
            SceneKind::Ai => [("chatgpt", "https://chatgpt.com/cdn-cgi/trace"), ("claude", "https://claude.ai/cdn-cgi/trace")]
                .into_iter()
                .find(|(id, _)| !excepted(id))
                .map(|(_, u)| u.to_string()),
            SceneKind::Other => Some("https://www.cloudflare.com/cdn-cgi/trace".into()),
            SceneKind::Video | SceneKind::Custom => None,
        })
    }

    /// 平台把 trace 响应正文交回；解析出 ip 与地区代码后回填出口。返回出口 IP。
    pub fn report_scene_trace(&self, scene_id: String, body: String, now_millis: i64) -> Result<String, MobileError> {
        let field = |k: &str| body.lines().find_map(|l| l.strip_prefix(k)).map(|v| v.trim().to_string()).filter(|v| !v.is_empty());
        let ip = field("ip=").filter(|v| v.parse::<std::net::IpAddr>().is_ok()).ok_or_else(|| MobileError::Invalid("trace: no ip".into()))?;
        let loc = field("loc=").filter(|v| v.len() == 2 && v != "XX").map(|v| v.to_ascii_uppercase());
        self.report_scene_exit(scene_id, ip.clone(), loc, now_millis)?;
        Ok(ip)
    }

    /// 场景来源（引导"优选 / 简单"与场景 sheet 的来源分段）。
    /// Auto：立即换到延迟缓存里最优的节点（当前地区优先，无选择时全库），返回需要平台执行的动作；
    /// 已是最优或没有测速数据时返回 None。Manual / SubscriptionGroup：只记录。
    pub fn set_scene_source(&self, scene_id: String, source: SceneSource, now_millis: i64) -> Result<Option<SceneApply>, MobileError> {
        let selected = {
            let mut sc = self.scenes.lock();
            let s = sc.get_mut(&scene_id)?;
            s.source = source;
            let sel = s.selected;
            sc.save()?;
            sel
        };
        if source != SceneSource::Auto || self.store().is_err() {
            return Ok(None);
        }
        let region = match selected {
            Some(id) => self.row_by_id(id).map(|r| r.region).unwrap_or_default(),
            None => String::new(),
        };
        let best = self.fastest_nodes(region, 1, now_millis, FRESH_MS)?.into_iter().find(|r| r.latency_ms >= 0).map(|r| r.row.id);
        let Some(best) = best.filter(|&b| Some(b) != selected) else { return Ok(None) };
        let apply = self.apply_scene_change(scene_id.clone(), best, now_millis)?;
        let mut sc = self.scenes.lock();
        sc.get_mut(&scene_id)?.source = SceneSource::Auto;
        sc.save()?;
        Ok(Some(apply))
    }

    /// 例外："Claude：US-Fixed-01"。node_id = None 删除例外。改完需重载。
    pub fn set_scene_exception(&self, scene_id: String, app_id: String, node_id: Option<u64>) -> Result<(), MobileError> {
        if scenes::app(&app_id).is_none() {
            return Err(MobileError::Invalid(format!("unknown app {app_id}")));
        }
        if let Some(n) = node_id {
            self.row_by_id(n)?;
        }
        let mut sc = self.scenes.lock();
        let s = sc.get_mut(&scene_id)?;
        s.exceptions.retain(|e| e.0 != app_id);
        if let Some(n) = node_id {
            s.exceptions.push((app_id, n));
        }
        sc.save()?;
        drop(sc);
        self.sync_override_layer()
    }

    /// 连接轨迹里的覆写（contract §13）。改完需重载；persistent = false 不落盘。
    pub fn override_host(&self, host: String, target: TraceTarget, scene_id: Option<String>, persistent: bool) -> Result<(), MobileError> {
        self.scenes.lock().set_override(HostOverride { host, target, scene_id, persistent })?;
        self.sync_override_layer()
    }

    pub fn host_override(&self, host: String) -> Option<HostOverride> {
        self.scenes.lock().override_for(&host).cloned()
    }

    /// 该 host 走哪个场景（内置应用目录），用于轨迹页"场景"一栏。
    pub fn scene_for_host(&self, host: String) -> Option<String> {
        let sc = self.scenes.lock();
        if let Some(o) = sc.override_for(&host) {
            return (o.target == TraceTarget::Scene).then(|| o.scene_id.clone()).flatten();
        }
        let app = scenes::app_of_host(&host)?;
        sc.scenes.iter().find(|s| s.kind == app.kind && s.selected.is_some()).map(|s| s.id.clone())
    }

    pub fn storage_info(&self) -> StorageInfo {
        let f = |n: &str| std::fs::metadata(self.dir.join(n)).map(|m| m.len() as i64).unwrap_or(0);
        StorageInfo {
            nodes_bytes: std::fs::read_to_string(self.dir.join("nodes.current")).map(|g| f(&format!("nodes.{}.zn", g.trim()))).unwrap_or(0),
            rules_bytes: dir_bytes(&self.dir.join("rules")),
            subscriptions_bytes: dir_bytes(&self.dir.join("subs")),
            cache_bytes: f("latency.bin") + f("scenes.json"),
        }
    }
}

#[cfg(test)]
pub(crate) mod tests {
    use super::*;
    use crate::latency::LatencySample;
    use crate::runtime_config::*;
    use crate::subs::FetchedSubscription;
    use serde_yaml::Value;

    fn opts() -> RuntimeOptions {
        RuntimeOptions {
            dns: DnsConfig { fake_ip: true, nameservers: vec!["https://dns.alidns.com/dns-query".into()], fallback: vec![], ipv6: false },
            tun: TunConfig { stack: TunStackKind::Gvisor, mtu: 9000, ipv6: false, strict_route: true, file_descriptor: None },
            mode: ProxyMode::Rule,
            controller_socket: "/data/zm.sock".into(),
            find_process: false,
            log_level: "warning".into(),
            local_proxy: None,
        }
    }

    pub fn setup() -> (tempfile::TempDir, std::sync::Arc<MobileCore>, String, Vec<NodeRow>) {
        let d = tempfile::tempdir().unwrap();
        let core = MobileCore::new(d.path().to_string_lossy().into()).unwrap();
        let mut a = String::from("proxies:\n");
        for (i, n) in ["美国 01", "美国 02", "美国 03", "日本 01"].iter().enumerate() {
            a += &format!("  - {{name: \"{n}\", server: a{i}.example, port: 443, type: trojan, password: p}}\n");
        }
        a += "proxy-groups:\n  - {name: 节点选择, type: select, proxies: [美国 01, 日本 01]}\nrules:\n  - DOMAIN-SUFFIX,google.com,节点选择\n  - MATCH,节点选择\n";
        // 第二个订阅也有一个 "美国 01"（同名不同服务器）
        let b = "proxies:\n  - {name: \"美国 01\", server: b0.example, port: 8443, type: vless, uuid: 00000000-0000-0000-0000-000000000000}\n";
        let f = |body: &str| FetchedSubscription { body: body.into(), userinfo: None, now_millis: 1 };
        let sa = core.import_subscription("A".into(), None, f(&a), 0, None).unwrap();
        core.import_subscription("B".into(), None, f(b), 0, None).unwrap();
        let q = core.query_nodes("美国".into()).unwrap();
        let rows = core.node_rows(q.token, 0, 10).unwrap().rows;
        assert_eq!(rows.len(), 4);
        let s: Vec<LatencySample> = rows.iter().enumerate().map(|(k, r)| LatencySample { id: r.id, ms: 50 + 10 * k as i32, at: 1000 }).collect();
        core.record_latencies(s).unwrap();
        (d, core, sa.id, rows)
    }

    #[test]
    fn subscription_rules_become_layer() {
        let (_d, core, sub, _rows) = setup();
        let t = core.test_rule("www.google.com".into()).unwrap();
        assert_eq!((t.layer_index, t.policy.as_str()), (Some(1), "节点选择"));
        let t = core.test_rule("example.org".into()).unwrap();
        assert_eq!((t.layer_index, t.rule.as_str(), t.policy.as_str()), (None, "MATCH", "节点选择"));
        let st = core.rule_stats();
        assert!(st.layers.iter().any(|l| l.kind == crate::rules::LayerKind::Subscription && l.note == "订阅规则" && l.count == 1), "{:?}", st.layers);
        core.delete_subscription(sub).unwrap();
        // 剩下的 B 订阅没有 rules：层为空，最终策略回 DIRECT
        assert_eq!(core.test_rule("www.google.com".into()).unwrap().policy, "DIRECT");
    }

    #[test]
    fn global_node_lands_in_config() {
        let (_d, core, sub, rows) = setup();
        let p = core.preview_global_change(rows[2].id).unwrap();
        assert_eq!(p.scene_id, None);
        assert!(p.affected_apps.contains(&"Claude".to_string()));
        let a = core.set_global_node(rows[2].id).unwrap();
        assert!(a.needs_reload);
        assert_eq!(a.group, "GLOBAL");
        assert_eq!(core.global_node(), Some(rows[2].id));
        let v: Value = serde_yaml::from_str(&core.runtime_config(sub, opts()).unwrap()).unwrap();
        let names: Vec<&str> = v["proxies"].as_sequence().unwrap().iter().filter_map(|p| p["name"].as_str()).collect();
        assert!(names.contains(&a.member.as_str()), "{names:?}");
        let b = core.set_global_node(rows[2].id).unwrap();
        assert!(!b.needs_reload, "已在配置里");
        assert_eq!(b.previous, Some(rows[2].id));
    }

    #[test]
    fn services_and_source() {
        let (_d, core, _sub, rows) = setup();
        let t: Vec<String> = core.scene_probe_targets("ai".into()).unwrap().into_iter().map(|x| x.app_id).collect();
        assert_eq!(t, vec!["chatgpt", "claude", "gemini"]);
        core.report_scene_service("ai".into(), "gemini".into(), true, 5).unwrap();
        core.report_scene_service("ai".into(), "claude".into(), false, 5).unwrap();
        core.report_scene_service("ai".into(), "claude".into(), false, 6).unwrap();
        assert!(core.report_scene_service("ai".into(), "nope".into(), true, 5).is_err());
        let ai = core.scenes(1000).unwrap().into_iter().find(|s| s.id == "ai").unwrap();
        let sv: Vec<(String, bool, i64)> = ai.services.iter().map(|x| (x.name.clone(), x.ok, x.checked_at)).collect();
        assert_eq!(sv, vec![("Claude".into(), false, 6), ("Gemini".into(), true, 5)]);
        assert!(ai.selected.is_none(), "上报服务健康不切换出口");

        // 优选：无选择时取全库最快
        let a = core.set_scene_source("video".into(), SceneSource::Auto, 1000).unwrap().expect("应换到最快节点");
        assert!(a.needs_reload);
        let v = core.scenes(1000).unwrap().into_iter().find(|s| s.id == "video").unwrap();
        assert_eq!(v.selected.unwrap().id, rows[0].id);
        assert_eq!(v.source, SceneSource::Auto);
        assert!(core.set_scene_source("video".into(), SceneSource::Auto, 1000).unwrap().is_none(), "已最优");
        assert!(core.set_scene_source("video".into(), SceneSource::Manual, 1000).unwrap().is_none());
        assert_eq!(core.scene_exit_probe("ai".into()).unwrap().as_deref(), Some("https://chatgpt.com/cdn-cgi/trace"));
        assert_eq!(core.scene_exit_probe("video".into()).unwrap(), None);
        let ip = core.report_scene_trace("ai".into(), "fl=1\nh=chatgpt.com\nip=198.51.100.7\nloc=us\n".into(), 7).unwrap();
        assert_eq!(ip, "198.51.100.7");
        let ai = core.scenes(1000).unwrap().into_iter().find(|s| s.id == "ai").unwrap();
        assert_eq!((ai.exit_ip.as_deref(), ai.exit_region.as_deref(), ai.tested_at), (Some("198.51.100.7"), Some("US"), Some(7)));
        assert!(core.report_scene_trace("ai".into(), "ip=nope".into(), 7).is_err());
        assert_eq!(core.scenes(1000).unwrap().into_iter().find(|s| s.id == "video").unwrap().source, SceneSource::Manual);
    }

    #[test]
    fn scene_flow_and_runtime_config() {
        let (_d, core, sub, rows) = setup();
        let sc = core.scenes(1000).unwrap();
        assert_eq!(sc.len(), 3);
        assert!(sc[0].selected.is_none());
        // 默认配置：场景组存在但不接管流量
        let v: Value = serde_yaml::from_str(&core.runtime_config(sub.clone(), opts()).unwrap()).unwrap();
        assert_eq!(v["rules"][0].as_str(), Some("DOMAIN-SUFFIX,google.com,节点选择"));
        assert_eq!(v["proxy-groups"][0]["proxies"][0].as_str(), Some("DIRECT"));

        // B 订阅的"美国 01"选给 AI：跨订阅注入
        let b_node = rows.iter().find(|r| r.protocol == "VLESS").unwrap().clone();
        let p = core.preview_scene_change("ai".into(), b_node.id).unwrap();
        assert_eq!(p.to_region, "US");
        assert!(p.affected_apps.contains(&"Claude".to_string()));
        let ap = core.apply_scene_change("ai".into(), b_node.id, 1000).unwrap();
        assert!(ap.needs_reload);
        assert_eq!(ap.previous, None);
        let cfg = core.runtime_config(sub.clone(), opts()).unwrap();
        let v: Value = serde_yaml::from_str(&cfg).unwrap();
        let g = v["proxy-groups"].as_sequence().unwrap().iter().find(|g| g["name"].as_str() == Some("Zephyr·AI")).unwrap();
        assert_eq!(g["proxies"][0].as_str(), Some(ap.member.as_str()));
        assert!(g["proxies"].as_sequence().unwrap().len() >= 3, "热备候选在组内");
        let names: Vec<&str> = v["proxies"].as_sequence().unwrap().iter().filter_map(|p| p["name"].as_str()).collect();
        assert!(names.contains(&ap.member.as_str()) && names.contains(&"美国 01"), "注入的与订阅自带的同名节点并存：{names:?}");
        assert!(v["rules"].as_sequence().unwrap().iter().any(|r| r.as_str() == Some("DOMAIN-SUFFIX,claude.ai,Zephyr·AI")));

        // 切到热备：不需重载；撤销回到上一个
        let hot = core.scenes(1000).unwrap()[0].clone();
        assert_eq!(hot.selected.as_ref().unwrap().id, b_node.id);
        assert!(hot.available >= 3);
        let standby_id = rows.iter().find(|r| r.id != b_node.id).unwrap().id;
        let ap2 = core.apply_scene_change("ai".into(), standby_id, 1000).unwrap();
        assert!(!ap2.needs_reload, "{ap2:?}");
        assert_eq!(ap2.previous, Some(b_node.id));
        assert!(!core.apply_scene_change("ai".into(), b_node.id, 1000).unwrap().needs_reload, "撤销也是热切换");

        // 例外 + 覆写
        core.set_scene_exception("ai".into(), "claude".into(), Some(standby_id)).unwrap();
        core.override_host("example.org".into(), TraceTarget::Direct, None, true).unwrap();
        let v: Value = serde_yaml::from_str(&core.runtime_config(sub.clone(), opts()).unwrap()).unwrap();
        let rules: Vec<&str> = v["rules"].as_sequence().unwrap().iter().filter_map(|r| r.as_str()).collect();
        assert_eq!(rules[0], "DOMAIN-SUFFIX,example.org,DIRECT", "覆写最先");
        let ic = rules.iter().position(|r| *r == "DOMAIN-SUFFIX,claude.ai,Zephyr·AI·Claude").unwrap();
        assert!(!rules.contains(&"DOMAIN-SUFFIX,claude.ai,Zephyr·AI"), "例外应用不再走场景组");
        assert!(ic < rules.iter().position(|r| *r == "DOMAIN-SUFFIX,openai.com,Zephyr·AI").unwrap());
        assert_eq!(core.preview_scene_change("ai".into(), standby_id).unwrap().unchanged_apps, vec!["Claude"]);
        assert_eq!(core.scene_for_host("api.openai.com".into()).as_deref(), Some("ai"));
        assert_eq!(core.scene_for_host("example.org".into()), None);
        // 规则页第 1 层与真实路由一致
        let st = core.rule_stats();
        assert_eq!(st.layers[0].name, "Zephyr 覆写");
        let t = core.test_rule("api.openai.com".into()).unwrap();
        assert_eq!((t.layer_index, t.policy.as_str()), (Some(0), "ai"));
        assert_eq!(core.test_rule("www.example.org".into()).unwrap().policy, "DIRECT");

        // "其他"接管 MATCH
        core.apply_scene_change("other".into(), standby_id, 1000).unwrap();
        let v: Value = serde_yaml::from_str(&core.runtime_config(sub, opts()).unwrap()).unwrap();
        assert_eq!(v["rules"].as_sequence().unwrap().last().unwrap().as_str(), Some("MATCH,Zephyr·其他"));

        // 持久化
        let st = core.storage_info();
        assert!(st.nodes_bytes > 0 && st.subscriptions_bytes > 0 && st.cache_bytes > 0);
        assert!(matches!(core.apply_scene_change("nope".into(), standby_id, 1000), Err(MobileError::SceneNotFound(_))));
    }

    /// 带场景的配置写出，给 mihomo-mobile 的 Go 测试用真 mihomo 加载（ZM_RUNTIME_CONFIG）。
    #[test]
    fn emit_for_mihomo_smoke_with_scenes() {
        let Ok(p) = std::env::var("ZM_RUNTIME_CONFIG") else { return };
        let (_d, core, sub, rows) = setup();
        core.apply_scene_change("ai".into(), rows[3].id, 1000).unwrap();
        core.set_scene_exception("ai".into(), "claude".into(), Some(rows[0].id)).unwrap();
        core.apply_scene_change("other".into(), rows[1].id, 1000).unwrap();
        core.override_host("example.org".into(), TraceTarget::Scene, Some("ai".into()), true).unwrap();
        std::fs::write(p, core.runtime_config(sub, opts()).unwrap()).unwrap();
    }
}
