//! GEOSITE / GEOIP 规则 → 规则页规则集之后的层（原型 LAYERS：geosite:cn、geoip:cn）。
//!
//! 数据来自 v2ray 格式的 geosite.dat / geoip.dat（protobuf），与 mihomo 的 geox 同源。核心不联网：
//! `geoSources()` 给出需要的文件、下载地址（订阅 geox-url 优先，否则 MetaCubeX meta-rules-dat）与是否到期；
//! 平台下载到 `path` 后调 `compileGeo(kind, nowMillis)`，核心只抽取订阅里 GEOSITE / GEOIP 用到的分类编译成层。
//! 正则域名（Regex）规则引擎不支持，跳过；@属性 不区分（同 mihomo 的不带属性写法）。

use crate::engine::MobileCore;
use crate::error::MobileError;
use crate::rule_providers::{load_manifest, save_manifest_pub, ManifestEntry, FIRST_PROVIDER_LAYER};
use crate::rules::LayerKind;
use serde_yaml::Value;

const WEEK_MS: i64 = 7 * 24 * 3_600_000;

#[derive(Debug, Clone, Copy, PartialEq, Eq, uniffi::Enum)]
pub enum GeoKind {
    Geosite,
    Geoip,
}

#[derive(Debug, Clone, PartialEq, uniffi::Record)]
pub struct GeoSource {
    pub kind: GeoKind,
    pub url: String,
    /// 平台把文件下载到这里（核心数据目录 geo/ 下）
    pub path: String,
    /// 订阅里用到的分类（小写）："cn"、"category-ads-all"
    pub codes: Vec<String>,
    pub due: bool,
}

/// 订阅规则里的 GEOSITE / GEOIP 行（按出现顺序去重）：(kind, code 小写, policy)。
pub fn geo_rules_in(body: &str) -> Vec<(GeoKind, String, String)> {
    let v: Value = serde_yaml::from_str(body).unwrap_or(Value::Null);
    let mut out: Vec<(GeoKind, String, String)> = vec![];
    for line in v.get("rules").and_then(|r| r.as_sequence()).into_iter().flatten().filter_map(|x| x.as_str()) {
        let p: Vec<&str> = line.split(',').map(str::trim).collect();
        if p.len() < 3 {
            continue;
        }
        let kind = match p[0].to_ascii_uppercase().as_str() {
            "GEOSITE" => GeoKind::Geosite,
            "GEOIP" => GeoKind::Geoip,
            _ => continue,
        };
        let code = p[1].to_ascii_lowercase();
        if !out.iter().any(|(k, c, _)| *k == kind && *c == code) {
            out.push((kind, code, p[2].to_string()));
        }
    }
    out
}

pub fn layer_name(kind: GeoKind, code: &str) -> String {
    match kind {
        GeoKind::Geosite => format!("geosite:{code}"),
        GeoKind::Geoip => format!("geoip:{code}"),
    }
}

fn geox_url(body: &str, kind: GeoKind) -> String {
    let v: Value = serde_yaml::from_str(body).unwrap_or(Value::Null);
    let key = match kind {
        GeoKind::Geosite => "geosite",
        GeoKind::Geoip => "geoip",
    };
    v.get("geox-url")
        .and_then(|g| g.get(key))
        .and_then(|u| u.as_str())
        .filter(|u| u.starts_with("https://"))
        .map(String::from)
        .unwrap_or_else(|| format!("https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest/{key}.dat"))
}

// ---------- 最小 protobuf 读取 ----------

struct Pb<'a> {
    b: &'a [u8],
    i: usize,
}

impl<'a> Pb<'a> {
    fn new(b: &'a [u8]) -> Self {
        Self { b, i: 0 }
    }
    fn varint(&mut self) -> Option<u64> {
        let mut v = 0u64;
        for s in (0..64).step_by(7) {
            let x = *self.b.get(self.i)?;
            self.i += 1;
            v |= u64::from(x & 0x7f) << s;
            if x & 0x80 == 0 {
                return Some(v);
            }
        }
        None
    }
    /// (字段号, 线类型, 长度型字段的内容)
    fn next(&mut self) -> Option<(u64, u8, &'a [u8], u64)> {
        if self.i >= self.b.len() {
            return None;
        }
        let key = self.varint()?;
        let (f, wt) = (key >> 3, (key & 7) as u8);
        match wt {
            0 => {
                let v = self.varint()?;
                Some((f, 0, &[], v))
            }
            1 => {
                self.i += 8;
                Some((f, 1, &[], 0))
            }
            2 => {
                let n = self.varint()? as usize;
                let s = self.b.get(self.i..self.i.checked_add(n)?)?;
                self.i += n;
                Some((f, 2, s, 0))
            }
            5 => {
                self.i += 4;
                Some((f, 5, &[], 0))
            }
            _ => None,
        }
    }
}

fn code_of(entry: &[u8]) -> Option<String> {
    let mut p = Pb::new(entry);
    while let Some((f, wt, s, _)) = p.next() {
        if f == 1 && wt == 2 {
            return std::str::from_utf8(s).ok().map(|x| x.to_ascii_lowercase());
        }
    }
    None
}

/// geosite.dat → 指定分类的规则文本（"DOMAIN-SUFFIX,x" 等，每行一条）。
pub fn geosite_text(dat: &[u8], code: &str) -> Result<String, MobileError> {
    let mut out = String::new();
    let mut found = false;
    let mut top = Pb::new(dat);
    while let Some((f, wt, entry, _)) = top.next() {
        if f != 1 || wt != 2 || code_of(entry).as_deref() != Some(code) {
            continue;
        }
        found = true;
        let mut e = Pb::new(entry);
        while let Some((f, wt, dom, _)) = e.next() {
            if f != 2 || wt != 2 {
                continue;
            }
            let (mut ty, mut val) = (0u64, "");
            let mut d = Pb::new(dom);
            while let Some((f, wt, s, v)) = d.next() {
                match (f, wt) {
                    (1, 0) => ty = v,
                    (2, 2) => val = std::str::from_utf8(s).unwrap_or(""),
                    _ => {}
                }
            }
            if val.is_empty() {
                continue;
            }
            let prefix = match ty {
                0 => "DOMAIN-KEYWORD",
                2 => "DOMAIN-SUFFIX",
                3 => "DOMAIN",
                _ => continue, // 1 = Regex
            };
            out.push_str(prefix);
            out.push(',');
            out.push_str(val);
            out.push('\n');
        }
    }
    if !found {
        return Err(MobileError::NotFound(format!("geosite:{code}")));
    }
    Ok(out)
}

/// geoip.dat → 指定国家代码的 CIDR 文本（每行一条）。reverse_match 的条目不支持，返回 Invalid。
pub fn geoip_text(dat: &[u8], code: &str) -> Result<String, MobileError> {
    let mut out = String::new();
    let mut found = false;
    let mut top = Pb::new(dat);
    while let Some((f, wt, entry, _)) = top.next() {
        if f != 1 || wt != 2 || code_of(entry).as_deref() != Some(code) {
            continue;
        }
        found = true;
        let mut e = Pb::new(entry);
        while let Some((f, wt, cidr, v)) = e.next() {
            if f == 3 && wt == 0 && v != 0 {
                return Err(MobileError::Invalid(format!("geoip:{code} reverse_match")));
            }
            if f != 2 || wt != 2 {
                continue;
            }
            let (mut ip, mut prefix): (&[u8], u64) = (&[], 0);
            let mut c = Pb::new(cidr);
            while let Some((f, wt, s, v)) = c.next() {
                match (f, wt) {
                    (1, 2) => ip = s,
                    (2, 0) => prefix = v,
                    _ => {}
                }
            }
            let addr = match ip.len() {
                4 => std::net::IpAddr::from(<[u8; 4]>::try_from(ip).unwrap()),
                16 => std::net::IpAddr::from(<[u8; 16]>::try_from(ip).unwrap()),
                _ => continue,
            };
            out.push_str(&format!("{addr}/{prefix}\n"));
        }
    }
    if !found {
        return Err(MobileError::NotFound(format!("geoip:{code}")));
    }
    Ok(out)
}

impl MobileCore {
    fn geo_dir(&self) -> std::path::PathBuf {
        self.dir.join("geo")
    }

    /// 规则集之后的 geo 层名称（按订阅里出现顺序）。prune 用。
    pub(crate) fn geo_layer_names(&self, body: &str) -> Vec<String> {
        geo_rules_in(body).into_iter().map(|(k, c, _)| layer_name(k, &c)).collect()
    }
}

#[uniffi::export]
impl MobileCore {
    pub fn geo_sources(&self, now_millis: i64) -> Vec<GeoSource> {
        let Some(body) = self.active_subscription_body() else { return vec![] };
        let rules = geo_rules_in(&body);
        let m = load_manifest(&self.dir);
        [GeoKind::Geosite, GeoKind::Geoip]
            .into_iter()
            .filter_map(|kind| {
                let codes: Vec<String> = rules.iter().filter(|(k, _, _)| *k == kind).map(|(_, c, _)| c.clone()).collect();
                if codes.is_empty() {
                    return None;
                }
                let file = match kind {
                    GeoKind::Geosite => "geosite.dat",
                    GeoKind::Geoip => "geoip.dat",
                };
                let path = self.geo_dir().join(file);
                // 到期：任一分类层未编译，或最旧一层超过一周
                let due = codes.iter().any(|c| {
                    let n = layer_name(kind, c);
                    m.values().find(|e| e.name == n).is_none_or(|e| now_millis - e.updated_at >= WEEK_MS)
                });
                Some(GeoSource { kind, url: geox_url(&body, kind), path: path.to_string_lossy().into(), codes, due })
            })
            .collect()
    }

    /// 平台把 dat 下载到 `geoSources()` 给的 path 后调用：编译该类全部用到的分类，返回编译的层数。
    pub fn compile_geo(&self, kind: GeoKind, now_millis: i64) -> Result<u32, MobileError> {
        let body = self.active_subscription_body().ok_or_else(|| MobileError::NotFound("subscription".into()))?;
        let file = match kind {
            GeoKind::Geosite => "geosite.dat",
            GeoKind::Geoip => "geoip.dat",
        };
        let path = self.geo_dir().join(file);
        let f = std::fs::File::open(&path)?;
        // 只读映射：几十 MB 的 dat 不整份读进堆
        let dat = unsafe { memmap2::Mmap::map(&f) }.map_err(|e| MobileError::Io(e.to_string()))?;
        let first = FIRST_PROVIDER_LAYER + crate::rule_providers::providers_in(&body).len() as u32;
        let mut m = load_manifest(&self.dir);
        let mut n = 0;
        for (i, (k, code, policy)) in geo_rules_in(&body).into_iter().enumerate() {
            if k != kind {
                continue;
            }
            let text = match kind {
                GeoKind::Geosite => geosite_text(&dat, &code),
                GeoKind::Geoip => geoip_text(&dat, &code),
            };
            let Ok(text) = text else { continue };
            let idx = first + i as u32;
            let lk = if kind == GeoKind::Geoip { LayerKind::Ip } else { LayerKind::Domain };
            let name = layer_name(kind, &code);
            let info = self.compile_rule_layer(idx, name.clone(), lk, "规则集 · 每周更新".into(), policy, text)?;
            m.insert(idx, ManifestEntry { name, count: info.count, updated_at: now_millis });
            n += 1;
        }
        save_manifest_pub(&self.dir, &m)?;
        let fin = self.rules.read().final_policy.clone();
        self.load_rules(fin)?;
        Ok(n)
    }
}

#[cfg(test)]
pub(crate) mod tests {
    use super::*;

    fn varint(mut v: u64, out: &mut Vec<u8>) {
        loop {
            let b = (v & 0x7f) as u8;
            v >>= 7;
            if v == 0 {
                out.push(b);
                return;
            }
            out.push(b | 0x80);
        }
    }
    fn field_bytes(f: u64, s: &[u8], out: &mut Vec<u8>) {
        varint(f << 3 | 2, out);
        varint(s.len() as u64, out);
        out.extend_from_slice(s);
    }
    fn field_var(f: u64, v: u64, out: &mut Vec<u8>) {
        varint(f << 3, out);
        varint(v, out);
    }

    pub fn geosite(entries: &[(&str, &[(u64, &str)])]) -> Vec<u8> {
        let mut top = vec![];
        for (code, doms) in entries {
            let mut e = vec![];
            field_bytes(1, code.as_bytes(), &mut e);
            for (ty, v) in *doms {
                let mut d = vec![];
                field_var(1, *ty, &mut d);
                field_bytes(2, v.as_bytes(), &mut d);
                field_bytes(2, &d, &mut e);
            }
            field_bytes(1, &e, &mut top);
        }
        top
    }

    pub fn geoip(entries: &[(&str, &[(&[u8], u64)])]) -> Vec<u8> {
        let mut top = vec![];
        for (code, cidrs) in entries {
            let mut e = vec![];
            field_bytes(1, code.as_bytes(), &mut e);
            for (ip, p) in *cidrs {
                let mut c = vec![];
                field_bytes(1, ip, &mut c);
                field_var(2, *p, &mut c);
                field_bytes(2, &c, &mut e);
            }
            field_bytes(1, &e, &mut top);
        }
        top
    }

    #[test]
    fn parses_dat() {
        let gs = geosite(&[("GOOGLE", &[(2, "google.com")]), ("CN", &[(2, "qq.com"), (3, "www.baidu.com"), (0, "taobao"), (1, "^re$")])]);
        assert_eq!(geosite_text(&gs, "cn").unwrap(), "DOMAIN-SUFFIX,qq.com\nDOMAIN,www.baidu.com\nDOMAIN-KEYWORD,taobao\n");
        assert!(geosite_text(&gs, "jp").is_err());
        let gi = geoip(&[("CN", &[(&[223, 5, 5, 0], 24), (&[0x24, 0x08, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0], 16)])]);
        assert_eq!(geoip_text(&gi, "cn").unwrap(), "223.5.5.0/24\n2408::/16\n");
    }

    #[test]
    fn geo_layers_after_providers() {
        use crate::subs::FetchedSubscription;
        let d = tempfile::tempdir().unwrap();
        let core = MobileCore::new(d.path().to_string_lossy().into()).unwrap();
        let sub = "proxies:\n  - {name: a, server: a.example, port: 443, type: trojan, password: p}\nrule-providers:\n  ads: {type: http, behavior: domain, url: 'https://r.example/ads.yaml'}\nrules:\n  - RULE-SET,ads,REJECT\n  - GEOSITE,CN,DIRECT\n  - GEOIP,CN,DIRECT,no-resolve\n  - MATCH,a\n";
        core.import_subscription("S".into(), None, FetchedSubscription { body: sub.into(), userinfo: None, now_millis: 1 }, 0, None).unwrap();
        let src = core.geo_sources(10);
        assert_eq!(src.len(), 2);
        assert!(src.iter().all(|s| s.due && s.codes == vec!["cn".to_string()]));
        assert!(src[0].url.ends_with("/geosite.dat"));
        std::fs::create_dir_all(std::path::Path::new(&src[0].path).parent().unwrap()).unwrap();
        std::fs::write(&src[0].path, geosite(&[("CN", &[(2, "qq.com")])])).unwrap();
        std::fs::write(&src[1].path, geoip(&[("CN", &[(&[223, 5, 5, 0], 24)])])).unwrap();
        assert_eq!(core.compile_geo(GeoKind::Geosite, 100).unwrap(), 1);
        assert_eq!(core.compile_geo(GeoKind::Geoip, 100).unwrap(), 1);
        let t = core.test_rule("im.qq.com".into()).unwrap();
        assert_eq!((t.layer_index, t.policy.as_str()), (Some(2), "DIRECT"), "ads 未拉取时不占位，按已加载层序号");
        let st = core.rule_stats();
        let names: Vec<&str> = st.layers.iter().map(|l| l.name.as_str()).collect();
        assert_eq!(names, vec!["Zephyr 覆写", "订阅规则", "geosite:cn", "geoip:cn"]);
        assert!(core.geo_sources(200).iter().all(|s| !s.due));
        assert!(core.geo_sources(100 + WEEK_MS).iter().all(|s| s.due));
    }
}
