//! 订阅存储（contract §7）：元数据 + 原始 YAML 缓存，更新前差异预览，增删改后重建节点库。
//!
//! 网络拉取由平台层做（URLSession / OkHttp：跟随系统代理/VPN 绕行策略、后台任务、证书策略），
//! 核心只接收「正文 + subscription-userinfo 响应头」。这样 iOS 扩展里不需要 TLS 栈，也便于后台刷新。
//!
//! 磁盘布局（data_dir 下）：
//!   subs/index.json      元数据数组（原子写：tmp + rename）
//!   subs/<id>.yaml       每个订阅最近一次成功的正文

use crate::error::MobileError;
use crate::nodes::fingerprint;
use crate::subscription::parse_proxies_yaml;
use serde::{Deserialize, Serialize};
use std::collections::HashSet;
use std::path::{Path, PathBuf};

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, uniffi::Record)]
pub struct SubscriptionDiff {
    pub added_nodes: i64,
    pub removed_nodes: i64,
    pub rule_changes: i64,
    /// Zephyr 覆写层不随订阅更新被冲掉（恒 true，核心保证）
    pub overrides_kept: bool,
    /// 平台层在更新后对受影响场景重测时置 true
    pub scenes_retested: bool,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, uniffi::Record)]
pub struct Subscription {
    pub id: String,
    pub name: String,
    /// 脱敏：只保留 scheme://host/…，查询参数与路径 token 去掉
    pub url: Option<String>,
    pub node_count: i64,
    pub used_bytes: Option<i64>,
    pub total_bytes: Option<i64>,
    pub remaining_bytes: Option<i64>,
    pub expires_at: Option<i64>,
    pub updated_at: Option<i64>,
    pub auto_update_hours: i32,
    pub last_diff: Option<SubscriptionDiff>,
}

#[derive(Debug, Clone, PartialEq, uniffi::Record)]
pub struct SubscriptionsSummary {
    pub count: i32,
    pub total_nodes: i64,
}

/// 平台拉取结果。
#[derive(Debug, Clone, uniffi::Record)]
pub struct FetchedSubscription {
    pub body: String,
    /// 原样的 `subscription-userinfo` 响应头（可为空）
    pub userinfo: Option<String>,
    /// 平台当前时间（毫秒），便于测试注入
    pub now_millis: i64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct Entry {
    /// 节点库内的订阅序号（u16，写进节点记录）
    pub slot: u16,
    pub meta: Subscription,
    /// 完整 URL（仅本地保存，不出核心）
    pub full_url: Option<String>,
}

pub(crate) struct SubStore {
    dir: PathBuf,
    pub entries: Vec<Entry>,
}

/// 脱敏：复用桌面端 `mask_url`（https://sub***com/***）。
pub fn redact_url(url: &str) -> String {
    zephyr_core::config::merge::mask_url(url.to_string())
}

/// 正文规整，全部复用桌面端：short-id 加引号 → 非 YAML 时尝试 base64 解码 → 去掉控制面字段。
/// 返回可安全落盘、之后可交给 mihomo 合并的 YAML。
pub fn normalize_body(body: &str) -> Result<String, MobileError> {
    use zephyr_core::config::subscription::{quote_short_id_values, try_decode_base64_content};
    let has_proxies = |t: &str| serde_yaml::from_str::<serde_yaml::Value>(t).ok().is_some_and(|v| v.get("proxies").is_some_and(|p| p.is_sequence()));
    let mut text = quote_short_id_values(body);
    if !has_proxies(&text) {
        match try_decode_base64_content(body) {
            Some(d) => text = quote_short_id_values(&d),
            None => return Err(MobileError::SubscriptionInvalid("不是 Clash/mihomo YAML，也不是 base64 编码的 YAML".into())),
        }
    }
    let mut v: serde_yaml::Value = serde_yaml::from_str(&text).map_err(|e| MobileError::SubscriptionInvalid(e.to_string()))?;
    let before = serde_yaml::to_string(&v).unwrap_or_default().len();
    zephyr_core::config::sanitizer::remove_control_plane_keys(&mut v);
    if serde_yaml::to_string(&v).unwrap_or_default().len() == before {
        return Ok(text); // 无改动：保留原文（注释、顺序）
    }
    serde_yaml::to_string(&v).map_err(|e| MobileError::SubscriptionInvalid(e.to_string()))
}

/// URL 校验：复用桌面端 `validate_subscription_url_basic`（scheme/host/控制字符/斜杠畸形）。
pub fn validate_url(url: &str) -> Result<(), MobileError> {
    zephyr_core::config::subscription::validate_subscription_url_basic(url).map(|_| ()).map_err(MobileError::SubscriptionInvalid)
}

/// `upload=1; download=2; total=3; expire=1700000000`（expire 单位秒）
pub fn parse_userinfo(h: &str) -> (Option<i64>, Option<i64>, Option<i64>) {
    let (mut up, mut down, mut total, mut expire) = (None, None, None, None);
    for kv in h.split([';', ',']) {
        let Some((k, v)) = kv.split_once('=') else { continue };
        let v: Option<i64> = v.trim().parse::<f64>().ok().map(|f| f as i64);
        match k.trim().to_ascii_lowercase().as_str() {
            "upload" => up = v,
            "download" => down = v,
            "total" => total = v,
            "expire" => expire = v.filter(|&x| x > 0).map(|s| s * 1000),
            _ => {}
        }
    }
    let used = match (up, down) {
        (None, None) => None,
        (a, b) => Some(a.unwrap_or(0) + b.unwrap_or(0)),
    };
    (used, total, expire)
}

fn rule_lines(yaml: &str) -> HashSet<String> {
    let v: serde_yaml::Value = match serde_yaml::from_str(yaml) {
        Ok(v) => v,
        Err(_) => return HashSet::new(),
    };
    v.get("rules")
        .and_then(|r| r.as_sequence())
        .map(|s| s.iter().filter_map(|x| x.as_str()).map(|x| x.split_whitespace().collect::<String>()).collect())
        .unwrap_or_default()
}

fn fingerprints(yaml: &str) -> Result<(HashSet<u64>, i64), MobileError> {
    let (nodes, _) = parse_proxies_yaml(yaml, 0)?;
    let n = nodes.len() as i64;
    Ok((nodes.iter().map(|x| fingerprint(&x.server, x.port, &x.protocol)).collect(), n))
}

/// 纯函数：新旧正文的差异。old = None 视为首次导入。
pub fn diff_bodies(old: Option<&str>, new: &str) -> Result<(SubscriptionDiff, i64), MobileError> {
    let (nf, n) = fingerprints(new)?;
    let (of, orules) = match old {
        Some(o) => (fingerprints(o).map(|x| x.0).unwrap_or_default(), rule_lines(o)),
        None => (HashSet::new(), HashSet::new()),
    };
    let nrules = rule_lines(new);
    let added = nf.difference(&of).count() as i64;
    let removed = of.difference(&nf).count() as i64;
    let rule_changes = nrules.symmetric_difference(&orules).count() as i64;
    Ok((SubscriptionDiff { added_nodes: added, removed_nodes: removed, rule_changes, overrides_kept: true, scenes_retested: false }, n))
}

impl SubStore {
    pub fn open(data_dir: &Path) -> Result<Self, MobileError> {
        let dir = data_dir.join("subs");
        std::fs::create_dir_all(&dir)?;
        let entries = match std::fs::read(dir.join("index.json")) {
            Ok(b) => serde_json::from_slice(&b).map_err(|e| MobileError::Corrupt(format!("subs/index.json: {e}")))?,
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => vec![],
            Err(e) => return Err(e.into()),
        };
        Ok(Self { dir, entries })
    }

    fn save(&self) -> Result<(), MobileError> {
        let tmp = self.dir.join("index.json.tmp");
        std::fs::write(&tmp, serde_json::to_vec_pretty(&self.entries).map_err(|e| MobileError::Io(e.to_string()))?)?;
        std::fs::rename(tmp, self.dir.join("index.json"))?;
        Ok(())
    }

    pub fn body_path(&self, slot: u16) -> PathBuf {
        self.dir.join(format!("{slot}.yaml"))
    }

    pub fn body(&self, slot: u16) -> Option<String> {
        std::fs::read_to_string(self.body_path(slot)).ok()
    }

    fn write_body(&self, slot: u16, body: &str) -> Result<(), MobileError> {
        let p = self.body_path(slot);
        let tmp = p.with_extension("yaml.tmp");
        std::fs::write(&tmp, body)?;
        std::fs::rename(tmp, p)?;
        Ok(())
    }

    pub fn find(&self, id: &str) -> Result<usize, MobileError> {
        self.entries.iter().position(|e| e.meta.id == id).ok_or_else(|| MobileError::SubscriptionNotFound(id.into()))
    }

    fn free_slot(&self) -> u16 {
        // 0 留给 mock / 无订阅
        (1..=u16::MAX).find(|s| !self.entries.iter().any(|e| e.slot == *s)).unwrap_or(u16::MAX)
    }

    pub fn list(&self) -> Vec<Subscription> {
        self.entries.iter().map(|e| e.meta.clone()).collect()
    }

    pub fn summary(&self) -> SubscriptionsSummary {
        SubscriptionsSummary { count: self.entries.len() as i32, total_nodes: self.entries.iter().map(|e| e.meta.node_count).sum() }
    }

    pub fn import(&mut self, name: String, url: Option<String>, f: &FetchedSubscription, auto_update_hours: i32) -> Result<Subscription, MobileError> {
        if let Some(u) = &url {
            validate_url(u)?;
        }
        let name = name.trim().to_string();
        if !name.is_empty() {
            zephyr_core::config::subscription::validate_subscription_name(&name).map_err(|e| MobileError::SubscriptionInvalid(e.to_string()))?;
        }
        let body = normalize_body(&f.body)?;
        let (diff, n) = diff_bodies(None, &body)?;
        if n == 0 {
            return Err(MobileError::SubscriptionInvalid("没有可用节点".into()));
        }
        let slot = self.free_slot();
        let (used, total, expire) = f.userinfo.as_deref().map(parse_userinfo).unwrap_or((None, None, None));
        let meta = Subscription {
            id: format!("sub-{slot}-{}", f.now_millis),
            name: if name.trim().is_empty() { url.as_deref().map(redact_url).unwrap_or_else(|| "订阅".into()) } else { name },
            url: url.as_deref().map(redact_url),
            node_count: n,
            used_bytes: used,
            total_bytes: total,
            remaining_bytes: total.zip(used).map(|(t, u)| (t - u).max(0)),
            expires_at: expire,
            updated_at: Some(f.now_millis),
            auto_update_hours,
            last_diff: Some(diff),
        };
        self.write_body(slot, &body)?;
        self.entries.push(Entry { slot, meta: meta.clone(), full_url: url });
        self.save()?;
        Ok(meta)
    }

    pub fn preview(&self, id: &str, f: &FetchedSubscription) -> Result<SubscriptionDiff, MobileError> {
        let e = &self.entries[self.find(id)?];
        Ok(diff_bodies(self.body(e.slot).as_deref(), &normalize_body(&f.body)?)?.0)
    }

    pub fn update(&mut self, id: &str, f: &FetchedSubscription) -> Result<SubscriptionDiff, MobileError> {
        let i = self.find(id)?;
        let slot = self.entries[i].slot;
        let body = normalize_body(&f.body)?;
        let (diff, n) = diff_bodies(self.body(slot).as_deref(), &body)?;
        if n == 0 {
            // 机场偶发返回空列表：拒绝覆盖，保留上次成功的正文
            return Err(MobileError::SubscriptionInvalid("新正文没有可用节点，已保留旧版本".into()));
        }
        self.write_body(slot, &body)?;
        let (used, total, expire) = f.userinfo.as_deref().map(parse_userinfo).unwrap_or((None, None, None));
        let m = &mut self.entries[i].meta;
        m.node_count = n;
        if f.userinfo.is_some() {
            m.used_bytes = used;
            m.total_bytes = total;
            m.remaining_bytes = total.zip(used).map(|(t, u)| (t - u).max(0));
            m.expires_at = expire;
        }
        m.updated_at = Some(f.now_millis);
        m.last_diff = Some(diff.clone());
        self.save()?;
        Ok(diff)
    }

    pub fn delete(&mut self, id: &str) -> Result<(), MobileError> {
        let i = self.find(id)?;
        let e = self.entries.remove(i);
        let _ = std::fs::remove_file(self.body_path(e.slot));
        self.save()
    }

    pub fn full_url(&self, id: &str) -> Result<Option<String>, MobileError> {
        Ok(self.entries[self.find(id)?].full_url.clone())
    }

    /// 自动更新到期的订阅 id（平台后台任务调用）。
    pub fn due(&self, now_millis: i64) -> Vec<String> {
        self.entries
            .iter()
            .filter(|e| e.meta.auto_update_hours > 0 && e.meta.updated_at.is_none_or(|t| now_millis - t >= e.meta.auto_update_hours as i64 * 3_600_000))
            .map(|e| e.meta.id.clone())
            .collect()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn y(nodes: &[(&str, &str, u16)], rules: &[&str]) -> String {
        let mut s = String::from("proxies:\n");
        for (n, sv, p) in nodes {
            s += &format!("  - {{name: \"{n}\", server: {sv}, port: {p}, type: vless}}\n");
        }
        s += "rules:\n";
        for r in rules {
            s += &format!("  - {r}\n");
        }
        s
    }
    fn f(body: String, t: i64) -> FetchedSubscription {
        FetchedSubscription { body, userinfo: Some("upload=100; download=900; total=10000; expire=1800000000".into()), now_millis: t }
    }

    #[test]
    fn userinfo_and_redact() {
        assert_eq!(parse_userinfo("upload=1; download=2; total=10; expire=5"), (Some(3), Some(10), Some(5000)));
        assert_eq!(parse_userinfo("total=10"), (None, Some(10), None));
        let r = redact_url("https://user:pw@sub.example.com/api/v1/client/subscribe?token=SECRET");
        assert!(!r.contains("SECRET") && !r.contains("pw") && !r.contains("subscribe"), "{r}");
        assert!(validate_url("ftp://x.example/s").is_err());
        assert!(validate_url("http:/sub").is_err());
    }

    #[test]
    fn body_base64_short_id_and_control_plane() {
        use base64::Engine;
        let yaml = "proxies:\n  - name: 香港 01\n    server: a.example\n    port: 443\n    type: vless\n    reality-opts:\n      short-id: 34010e92\n";
        let b64 = base64::engine::general_purpose::STANDARD.encode(yaml);
        let n = normalize_body(&b64).unwrap();
        assert!(n.contains("\"34010e92\"") || n.contains("'34010e92'"), "short-id 保持字符串：{n}");
        assert!(normalize_body("not yaml at all ###").is_err());
        let evil = format!("{yaml}external-ui: /tmp/x\nexternal-controller-tls: 0.0.0.0:9443\n");
        let n = normalize_body(&evil).unwrap();
        assert!(!n.contains("external-controller-tls") && !n.contains("external-ui"), "控制面字段被清掉：{n}");
        assert!(n.contains("a.example"));
    }

    #[test]
    fn import_preview_update_delete_persist() {
        let d = tempfile::tempdir().unwrap();
        let mut s = SubStore::open(d.path()).unwrap();
        let v1 = y(&[("香港 01", "a.example", 443), ("日本 01", "b.example", 443), ("美国 01", "c.example", 443)], &["DOMAIN,x.com,P", "MATCH,P"]);
        let sub = s.import("Nebula".into(), Some("https://sub.example.com/s?token=T".into()), &f(v1, 1000), 24).unwrap();
        assert_eq!(sub.node_count, 3);
        assert_eq!(sub.remaining_bytes, Some(9000));
        assert_eq!(sub.expires_at, Some(1_800_000_000_000));
        assert!(!sub.url.as_deref().unwrap().contains("token"));
        assert_eq!(s.full_url(&sub.id).unwrap().as_deref(), Some("https://sub.example.com/s?token=T"));

        let v2 = y(&[("香港 01", "a.example", 443), ("日本 01 改名", "b.example", 443), ("新加坡 01", "d.example", 443), ("新加坡 02", "e.example", 443)], &["DOMAIN,x.com,P", "DOMAIN,y.com,P", "MATCH,P"]);
        let p = s.preview(&sub.id, &f(v2.clone(), 2000)).unwrap();
        assert_eq!((p.added_nodes, p.removed_nodes, p.rule_changes), (2, 1, 1), "改名不算增删（指纹=server+port+协议）");
        assert_eq!(s.list()[0].node_count, 3, "预览不落盘");

        let u = s.update(&sub.id, &f(v2, 2000)).unwrap();
        assert_eq!(u, p);
        let empty = y(&[], &[]);
        assert!(s.update(&sub.id, &f(empty, 3000)).is_err(), "空列表拒绝覆盖");

        let s2 = SubStore::open(d.path()).unwrap();
        assert_eq!(s2.summary(), SubscriptionsSummary { count: 1, total_nodes: 4 });
        assert_eq!(s2.list()[0].last_diff.as_ref().unwrap().added_nodes, 2);
        assert_eq!(s2.due(2000 + 23 * 3_600_000), Vec::<String>::new());
        assert_eq!(s2.due(2000 + 24 * 3_600_000), vec![sub.id.clone()]);

        let mut s3 = s2;
        s3.delete(&sub.id).unwrap();
        assert!(matches!(s3.delete(&sub.id), Err(MobileError::SubscriptionNotFound(_))));
        assert_eq!(SubStore::open(d.path()).unwrap().summary().count, 0);
    }
}
