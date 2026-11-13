//! 导入载荷解析（contract §15）：二维码 / 剪贴板 / 深链里的字符串 → 待导入的订阅列表。
//!
//! 接受：
//! 1. `zephyr://import?url=<pct>&name=<pct>&auto=<h>`（单条；桌面"同步到手机"二维码 v1 的默认形态）
//! 2. `zephyr://import?v=1&d=<base64url(JSON)>`（多条；JSON = `{"v":1,"subs":[{"name","url","auto"}]}`）
//! 3. `clash://install-config?url=…&name=…`（含 `clashmeta://`、`mihomo://`，社区通用格式）
//! 4. 裸 `http(s)://…` 订阅链接
//!
//! 只做解析与校验，不发请求；平台层拿到 `ImportItem.url` 后照 §14 的流程拉取再 `importSubscription`。

use base64::Engine as _;

use crate::error::MobileError;

/// 单个载荷最多条数、最大长度（二维码 L 档上限约 2.9 KB，留余量）。
pub const MAX_ITEMS: usize = 20;
pub const MAX_PAYLOAD_BYTES: usize = 4096;

#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct ImportItem {
    /// 订阅名；载荷未给则 None（平台层用脱敏 URL 兜底，与 importSubscription 一致）
    pub name: Option<String>,
    /// 完整订阅 URL（仅 http/https）
    pub url: String,
    /// 自动更新间隔（小时）；载荷未给则 None（平台层用默认值）
    pub auto_update_hours: Option<i32>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, uniffi::Enum)]
pub enum ImportPayloadKind {
    /// zephyr://import（桌面同步）
    Zephyr,
    /// clash:// / clashmeta:// / mihomo:// install-config
    ClashInstall,
    /// 裸 http(s) 链接
    Url,
}

#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct ImportPayload {
    pub kind: ImportPayloadKind,
    pub items: Vec<ImportItem>,
}

#[derive(serde::Deserialize)]
struct BatchJson {
    v: u32,
    subs: Vec<BatchSub>,
}

#[derive(serde::Deserialize)]
struct BatchSub {
    name: Option<String>,
    url: String,
    auto: Option<i32>,
}

/// contract §15：`parseImportPayload(payload) -> ImportPayload`。无法识别 / 校验失败 → `Invalid` / `SubscriptionInvalid`。
#[uniffi::export]
pub fn parse_import_payload(payload: String) -> Result<ImportPayload, MobileError> {
    let p = payload.trim();
    if p.is_empty() {
        return Err(MobileError::Invalid("空载荷".into()));
    }
    if p.len() > MAX_PAYLOAD_BYTES {
        return Err(MobileError::Invalid("载荷过长".into()));
    }
    let lower = p.to_ascii_lowercase();
    let (kind, items) = if let Some(rest) = strip_scheme_host(p, &lower, &["zephyr://import"]) {
        (ImportPayloadKind::Zephyr, parse_zephyr(rest)?)
    } else if let Some(rest) = strip_scheme_host(p, &lower, &["clash://install-config", "clashmeta://install-config", "mihomo://install-config"]) {
        (ImportPayloadKind::ClashInstall, vec![item_from_query(rest)?])
    } else if lower.starts_with("http://") || lower.starts_with("https://") {
        (ImportPayloadKind::Url, vec![finish_item(None, p.to_string(), None)?])
    } else {
        return Err(MobileError::Invalid("不是订阅链接或 Zephyr 导入码".into()));
    };
    if items.is_empty() {
        return Err(MobileError::Invalid("载荷里没有订阅".into()));
    }
    if items.len() > MAX_ITEMS {
        return Err(MobileError::Invalid(format!("一次最多导入 {MAX_ITEMS} 个订阅")));
    }
    Ok(ImportPayload { kind, items })
}

/// 匹配前缀（大小写不敏感），返回 `?` 之后的查询串（无查询串返回空串）。
fn strip_scheme_host<'a>(orig: &'a str, lower: &str, prefixes: &[&str]) -> Option<&'a str> {
    for pre in prefixes {
        if lower.starts_with(pre) {
            let rest = &orig[pre.len()..];
            let rest = rest.strip_prefix('/').unwrap_or(rest);
            if rest.is_empty() {
                return Some("");
            }
            return rest.strip_prefix('?').map(|q| q.split('#').next().unwrap_or(""));
        }
    }
    None
}

fn query_pairs(q: &str) -> Result<Vec<(String, String)>, MobileError> {
    q.split('&').filter(|s| !s.is_empty()).map(|kv| {
        let (k, v) = kv.split_once('=').unwrap_or((kv, ""));
        Ok((pct_decode(k)?, pct_decode(v)?))
    }).collect()
}

fn get<'a>(pairs: &'a [(String, String)], key: &str) -> Option<&'a str> {
    pairs.iter().find(|(k, _)| k == key).map(|(_, v)| v.as_str())
}

fn parse_zephyr(q: &str) -> Result<Vec<ImportItem>, MobileError> {
    let pairs = query_pairs(q)?;
    match get(&pairs, "v") {
        None | Some("1") => {}
        Some(v) => return Err(MobileError::Invalid(format!("导入码版本 v{v} 过新，请更新 Zephyr"))),
    }
    if let Some(d) = get(&pairs, "d") {
        let raw = base64::engine::general_purpose::URL_SAFE_NO_PAD
            .decode(d.trim_end_matches('='))
            .map_err(|_| MobileError::Invalid("导入码数据损坏".into()))?;
        let batch: BatchJson = serde_json::from_slice(&raw).map_err(|_| MobileError::Invalid("导入码数据损坏".into()))?;
        if batch.v != 1 {
            return Err(MobileError::Invalid(format!("导入码版本 v{} 过新，请更新 Zephyr", batch.v)));
        }
        return batch.subs.into_iter().map(|s| finish_item(s.name, s.url, s.auto)).collect();
    }
    Ok(vec![item_from_pairs(&pairs)?])
}

fn item_from_query(q: &str) -> Result<ImportItem, MobileError> {
    item_from_pairs(&query_pairs(q)?)
}

fn item_from_pairs(pairs: &[(String, String)]) -> Result<ImportItem, MobileError> {
    let url = get(pairs, "url").ok_or_else(|| MobileError::Invalid("缺少 url".into()))?;
    let auto = match get(pairs, "auto") {
        None | Some("") => None,
        Some(a) => Some(a.parse::<i32>().map_err(|_| MobileError::Invalid("auto 不是整数".into()))?),
    };
    finish_item(get(pairs, "name").map(str::to_string), url.to_string(), auto)
}

fn finish_item(name: Option<String>, url: String, auto: Option<i32>) -> Result<ImportItem, MobileError> {
    let url = url.trim().to_string();
    crate::subs::validate_url(&url)?;
    let name = name.map(|n| n.trim().to_string()).filter(|n| !n.is_empty());
    if let Some(n) = &name {
        zephyr_core::config::subscription::validate_subscription_name(n).map_err(|e| MobileError::SubscriptionInvalid(e.to_string()))?;
    }
    if let Some(h) = auto {
        if !(0..=24 * 30).contains(&h) {
            return Err(MobileError::Invalid("auto 超出范围（0–720 小时）".into()));
        }
    }
    Ok(ImportItem { name, url, auto_update_hours: auto })
}

fn pct_decode(s: &str) -> Result<String, MobileError> {
    let b = s.as_bytes();
    let mut out = Vec::with_capacity(b.len());
    let mut i = 0;
    while i < b.len() {
        match b[i] {
            b'%' if i + 2 < b.len() => {
                let hex = std::str::from_utf8(&b[i + 1..i + 3]).ok().and_then(|h| u8::from_str_radix(h, 16).ok());
                match hex {
                    Some(v) => {
                        out.push(v);
                        i += 3;
                    }
                    None => return Err(MobileError::Invalid("百分号编码错误".into())),
                }
            }
            b'%' => return Err(MobileError::Invalid("百分号编码错误".into())),
            b'+' => {
                out.push(b' ');
                i += 1;
            }
            c => {
                out.push(c);
                i += 1;
            }
        }
    }
    String::from_utf8(out).map_err(|_| MobileError::Invalid("不是 UTF-8".into()))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn b64(s: &str) -> String {
        base64::engine::general_purpose::URL_SAFE_NO_PAD.encode(s)
    }

    #[test]
    fn bare_url() {
        let p = parse_import_payload("  https://sub.example.com/api?token=abc  ".into()).unwrap();
        assert_eq!(p.kind, ImportPayloadKind::Url);
        assert_eq!(p.items, vec![ImportItem { name: None, url: "https://sub.example.com/api?token=abc".into(), auto_update_hours: None }]);
    }

    #[test]
    fn zephyr_single() {
        let p = parse_import_payload("zephyr://import?url=https%3A%2F%2Fsub.example.com%2Fa%3Ftoken%3Dx%26y%3D1&name=Nebula%20Cloud&auto=12".into()).unwrap();
        assert_eq!(p.kind, ImportPayloadKind::Zephyr);
        assert_eq!(p.items[0].url, "https://sub.example.com/a?token=x&y=1");
        assert_eq!(p.items[0].name.as_deref(), Some("Nebula Cloud"));
        assert_eq!(p.items[0].auto_update_hours, Some(12));
    }

    #[test]
    fn zephyr_batch() {
        let d = b64(r#"{"v":1,"subs":[{"name":"A","url":"https://a.example.com/s"},{"url":"https://b.example.com/s","auto":24}]}"#);
        let p = parse_import_payload(format!("ZEPHYR://import/?v=1&d={d}")).unwrap();
        assert_eq!(p.items.len(), 2);
        assert_eq!(p.items[0].name.as_deref(), Some("A"));
        assert_eq!(p.items[1].auto_update_hours, Some(24));
    }

    #[test]
    fn clash_install_config() {
        for s in ["clash", "clashmeta", "mihomo"] {
            let p = parse_import_payload(format!("{s}://install-config?url=https%3A%2F%2Fx.example.com%2Fs&name=X")).unwrap();
            assert_eq!(p.kind, ImportPayloadKind::ClashInstall);
            assert_eq!(p.items[0].url, "https://x.example.com/s");
        }
    }

    #[test]
    fn rejects() {
        for bad in [
            "",
            "hello",
            "zephyr://import?v=2&url=https%3A%2F%2Fa.example.com",
            "zephyr://import?name=x",
            "zephyr://import?url=ftp%3A%2F%2Fa.example.com",
            "zephyr://import?url=https%3A%2F%2Fa.example.com&auto=abc",
            "zephyr://import?url=https%3A%2F%2Fa.example.com&auto=99999",
            "zephyr://import?d=!!!",
            "zephyr://import?url=%ZZ",
            "zephyr://import?url=%4",
        ] {
            assert!(parse_import_payload(bad.into()).is_err(), "{bad}");
        }
        let many: Vec<String> = (0..21).map(|i| format!(r#"{{"url":"https://s{i}.example.com/x"}}"#)).collect();
        let d = b64(&format!(r#"{{"v":1,"subs":[{}]}}"#, many.join(",")));
        assert!(parse_import_payload(format!("zephyr://import?d={d}")).is_err());
    }

    /// contract/fixtures/import-payload-v1.json 逐条比对（两端 Mock / UI 预解析共用同一份样本）。
    #[test]
    fn fixtures() {
        let doc: serde_json::Value = serde_json::from_str(include_str!("../../contract/fixtures/import-payload-v1.json")).unwrap();
        for case in doc["cases"].as_array().unwrap() {
            let id = case["id"].as_str().unwrap();
            let got = parse_import_payload(case["input"].as_str().unwrap().to_string());
            if let Some(ok) = case.get("ok") {
                let p = got.unwrap_or_else(|e| panic!("{id}: {e}"));
                let kind = match p.kind {
                    ImportPayloadKind::Zephyr => "zephyr",
                    ImportPayloadKind::ClashInstall => "clashInstall",
                    ImportPayloadKind::Url => "url",
                };
                assert_eq!(kind, ok["kind"].as_str().unwrap(), "{id}");
                let want = ok["items"].as_array().unwrap();
                assert_eq!(p.items.len(), want.len(), "{id}");
                for (g, w) in p.items.iter().zip(want) {
                    assert_eq!(g.name.as_deref(), w["name"].as_str(), "{id}");
                    assert_eq!(g.url, w["url"].as_str().unwrap(), "{id}");
                    assert_eq!(g.auto_update_hours.map(i64::from), w["autoUpdateHours"].as_i64(), "{id}");
                }
            } else {
                let e = got.err().unwrap_or_else(|| panic!("{id}: 应失败"));
                let code = match e {
                    MobileError::Invalid(_) => "invalid",
                    MobileError::SubscriptionInvalid(_) => "subscription_invalid",
                    other => panic!("{id}: 意外错误 {other}"),
                };
                assert_eq!(code, case["err"].as_str().unwrap(), "{id}");
            }
        }
    }
}
