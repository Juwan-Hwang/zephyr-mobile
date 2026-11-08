//! 规则集（rule-providers）→ 规则页第 3 层起（原型 LAYERS：OpenAI / 广告与跟踪 / 威胁情报 / geosite:cn / geoip:cn）。
//!
//! 真实路由由 mihomo 自己拉取规则集；这里编译一份给规则页计数、testRule 与命令搜索用。
//! 核心不联网：`ruleProviders()` 列出生效订阅里被 RULE-SET 引用的 http 规则集（按首次引用顺序，层序号 = 2 + 位置），
//! 平台按 url 拉正文后调 `compileRuleProvider(name, body, nowMillis)`。mrs 二进制格式暂不支持（返回 Invalid）。
//! rules/providers.json 记录 序号 → 名称/条数/时间；订阅变化后序号对不上的旧层在 `sync_subscription_rules` 里删除。

use crate::engine::MobileCore;
use crate::error::MobileError;
use crate::rules::{LayerKind, RuleLayerInfo};
use serde::{Deserialize, Serialize};
use serde_yaml::Value;
use std::collections::BTreeMap;
use std::path::Path;

pub const FIRST_PROVIDER_LAYER: u32 = 2;

#[derive(Debug, Clone, PartialEq, uniffi::Record)]
pub struct RuleProvider {
    pub name: String,
    /// 完整地址（只在本机用于拉取，不进日志、不上传）
    pub url: String,
    /// domain | ipcidr | classical
    pub behavior: String,
    /// yaml | text | mrs
    pub format: String,
    pub interval_secs: i64,
    /// RULE-SET 行上的策略
    pub policy: String,
    pub layer_index: u32,
    pub rule_count: Option<u64>,
    pub updated_at: Option<i64>,
    /// 到期需要（重新）拉取
    pub due: bool,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub(crate) struct ManifestEntry {
    pub name: String,
    pub count: u64,
    pub updated_at: i64,
}

pub(crate) fn manifest_path(dir: &Path) -> std::path::PathBuf {
    dir.join("rules").join("providers.json")
}

pub(crate) fn load_manifest(dir: &Path) -> BTreeMap<u32, ManifestEntry> {
    std::fs::read(manifest_path(dir)).ok().and_then(|b| serde_json::from_slice(&b).ok()).unwrap_or_default()
}

pub(crate) fn save_manifest_pub(dir: &Path, m: &BTreeMap<u32, ManifestEntry>) -> Result<(), MobileError> {
    save_manifest(dir, m)
}

fn save_manifest(dir: &Path, m: &BTreeMap<u32, ManifestEntry>) -> Result<(), MobileError> {
    let p = manifest_path(dir);
    let tmp = p.with_extension("tmp");
    std::fs::write(&tmp, serde_json::to_vec(m).map_err(|e| MobileError::Io(e.to_string()))?)?;
    std::fs::rename(tmp, p)?;
    Ok(())
}

/// 订阅正文 → 被 RULE-SET 引用的 http 规则集（按首次引用顺序）。
pub fn providers_in(body: &str) -> Vec<(String, String, String, String, i64, String)> {
    let v: Value = serde_yaml::from_str(body).unwrap_or(Value::Null);
    let Some(defs) = v.get("rule-providers").and_then(|x| x.as_mapping()) else { return vec![] };
    let mut out: Vec<(String, String, String, String, i64, String)> = Vec::new();
    for line in v.get("rules").and_then(|r| r.as_sequence()).into_iter().flatten().filter_map(|x| x.as_str()) {
        let parts: Vec<&str> = line.split(',').map(str::trim).collect();
        if parts.len() < 3 || !parts[0].eq_ignore_ascii_case("RULE-SET") || out.iter().any(|p| p.0 == parts[1]) {
            continue;
        }
        let Some(d) = defs.get(parts[1]) else { continue };
        let s = |k: &str| d.get(k).and_then(|x| x.as_str()).unwrap_or("").to_string();
        if s("type") != "http" || s("url").is_empty() {
            continue;
        }
        let behavior = if s("behavior").is_empty() { "classical".into() } else { s("behavior") };
        let format = if s("format").is_empty() { "yaml".into() } else { s("format") };
        let interval = d.get("interval").and_then(|x| x.as_i64()).unwrap_or(86_400);
        out.push((parts[1].to_string(), s("url"), behavior, format, interval, parts[2].to_string()));
    }
    out
}

fn cadence(interval: i64) -> &'static str {
    match interval {
        i if i <= 0 => "规则集 · 手动更新",
        i if i <= 3_600 => "规则集 · 每小时更新",
        i if i <= 86_400 => "规则集 · 每天更新",
        i if i <= 604_800 => "规则集 · 每周更新",
        _ => "规则集 · 每月更新",
    }
}

impl MobileCore {
    pub(crate) fn active_subscription_body(&self) -> Option<String> {
        let s = self.subs.lock();
        s.entries.first().and_then(|e| s.body(e.slot))
    }

    /// 订阅变化后：序号上的规则集换了名字（或已不存在）的旧层删除。
    pub(crate) fn prune_provider_layers(&self) -> Result<(), MobileError> {
        let want: Vec<String> = self
            .active_subscription_body()
            .map(|b| providers_in(&b).into_iter().map(|p| p.0).chain(self.geo_layer_names(&b)).collect())
            .unwrap_or_default();
        let mut m = load_manifest(&self.dir);
        let rules_dir = self.dir.join("rules");
        if let Ok(rd) = std::fs::read_dir(&rules_dir) {
            for e in rd.flatten() {
                let p = e.path();
                let Some(idx) = p.file_stem().and_then(|s| s.to_str()).and_then(|s| s.parse::<u32>().ok()) else { continue };
                if idx < FIRST_PROVIDER_LAYER || p.extension().is_none_or(|x| x != "zr") {
                    continue;
                }
                let expected = want.get((idx - FIRST_PROVIDER_LAYER) as usize);
                if expected.is_none() || m.get(&idx).map(|x| &x.name) != expected {
                    let _ = std::fs::remove_file(&p);
                    m.remove(&idx);
                }
            }
        }
        m.retain(|idx, e| want.get((idx - FIRST_PROVIDER_LAYER) as usize) == Some(&e.name));
        save_manifest(&self.dir, &m)
    }
}

#[uniffi::export]
impl MobileCore {
    pub fn rule_providers(&self, now_millis: i64) -> Vec<RuleProvider> {
        let Some(body) = self.active_subscription_body() else { return vec![] };
        let m = load_manifest(&self.dir);
        providers_in(&body)
            .into_iter()
            .enumerate()
            .map(|(i, (name, url, behavior, format, interval, policy))| {
                let idx = FIRST_PROVIDER_LAYER + i as u32;
                let e = m.get(&idx).filter(|e| e.name == name);
                let due = match e {
                    None => true,
                    Some(e) => interval > 0 && now_millis - e.updated_at >= interval * 1000,
                };
                RuleProvider { name, url, behavior, format, interval_secs: interval, policy, layer_index: idx, rule_count: e.map(|e| e.count), updated_at: e.map(|e| e.updated_at), due }
            })
            .collect()
    }

    /// 平台拉到规则集正文后交回：编译为对应层并热加载全部规则。
    pub fn compile_rule_provider(&self, name: String, body: String, now_millis: i64) -> Result<RuleLayerInfo, MobileError> {
        // 平台可能并发调用（导入后自动刷新 + 手动刷新）：串行化写层文件与清单
        static WRITE: std::sync::Mutex<()> = std::sync::Mutex::new(());
        let _g = WRITE.lock().unwrap_or_else(|e| e.into_inner());
        let p = self.rule_providers(now_millis).into_iter().find(|p| p.name == name).ok_or_else(|| MobileError::NotFound(format!("rule provider {name}")))?;
        if p.format == "mrs" {
            return Err(MobileError::Invalid("mrs 格式暂不支持".into()));
        }
        let kind = if p.behavior == "ipcidr" { LayerKind::Ip } else { LayerKind::Domain };
        let info = self.compile_rule_layer(p.layer_index, name.clone(), kind, cadence(p.interval_secs).into(), p.policy, body)?;
        let mut m = load_manifest(&self.dir);
        m.insert(p.layer_index, ManifestEntry { name, count: info.count, updated_at: now_millis });
        save_manifest(&self.dir, &m)?;
        let fin = self.rules.read().final_policy.clone();
        self.load_rules(fin)?;
        Ok(info)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::subs::FetchedSubscription;

    const SUB: &str = "proxies:\n  - {name: a, server: a.example, port: 443, type: trojan, password: p}\nrule-providers:\n  openai: {type: http, behavior: domain, url: 'https://r.example/openai.yaml', interval: 86400}\n  cn-ip: {type: http, behavior: ipcidr, format: text, url: 'https://r.example/cn.txt', interval: 604800}\n  local: {type: file, behavior: domain, path: ./x.yaml}\n  unused: {type: http, behavior: domain, url: 'https://r.example/u.yaml'}\nrules:\n  - DOMAIN-SUFFIX,google.com,a\n  - RULE-SET,openai,a\n  - RULE-SET,local,DIRECT\n  - RULE-SET,cn-ip,DIRECT\n  - RULE-SET,openai,DIRECT\n  - MATCH,a\n";

    #[test]
    fn providers_compile_into_layers() {
        let d = tempfile::tempdir().unwrap();
        let core = MobileCore::new(d.path().to_string_lossy().into()).unwrap();
        let f = FetchedSubscription { body: SUB.into(), userinfo: None, now_millis: 1 };
        let sub = core.import_subscription("S".into(), None, f, 0, None).unwrap();
        let ps = core.rule_providers(1000);
        assert_eq!(ps.iter().map(|p| (p.name.as_str(), p.layer_index, p.policy.as_str())).collect::<Vec<_>>(), vec![("openai", 2, "a"), ("cn-ip", 3, "DIRECT")]);
        assert!(ps.iter().all(|p| p.due && p.rule_count.is_none()));

        let i = core.compile_rule_provider("openai".into(), "payload:\n  - '+.openai.com'\n  - 'chatgpt.com'\n".into(), 5000).unwrap();
        assert_eq!(i.count, 2);
        core.compile_rule_provider("cn-ip".into(), "1.0.1.0/24\n# c\n223.5.5.0/24\n".into(), 5000).unwrap();
        let t = core.test_rule("api.openai.com".into()).unwrap();
        assert_eq!((t.layer_index, t.policy.as_str()), (Some(2), "a"));
        let t = core.test_rule("223.5.5.5".into()).unwrap();
        assert_eq!((t.layer_index, t.policy.as_str()), (Some(3), "DIRECT"));
        let st = core.rule_stats();
        assert_eq!(st.layers.len(), 4);
        assert_eq!(st.layers[2].note, "规则集 · 每天更新");
        assert_eq!(st.layers[3].note, "规则集 · 每周更新");
        let ps = core.rule_providers(6000);
        assert_eq!((ps[0].rule_count, ps[0].due), (Some(2), false));
        assert!(core.rule_providers(5000 + 86_400_000).iter().find(|p| p.name == "openai").unwrap().due);
        assert!(core.compile_rule_provider("nope".into(), String::new(), 1).is_err());

        // 订阅换掉：规则集层被清理
        let f2 = FetchedSubscription { body: "proxies:\n  - {name: a, server: a.example, port: 443, type: trojan, password: p}\nrules:\n  - MATCH,DIRECT\n".into(), userinfo: None, now_millis: 2 };
        core.update_subscription(sub.id, f2, None).unwrap();
        assert_eq!(core.rule_stats().layers.len(), 2);
        assert!(core.rule_providers(1).is_empty());
    }
}
