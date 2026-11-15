//! 订阅解析：Clash/mihomo YAML 的 proxies 列表 → NodeInput。只取索引所需字段；完整配置仍交给 mihomo。

use crate::error::MobileError;
use crate::nodes::NodeInput;

const TAGS: &[&str] = &["IPLC", "IEPL", "BGP", "家宽", "原生", "专线", "中转", "直连"];

pub fn parse_multiplier(name: &str) -> u8 {
    let lc = name.to_lowercase();
    for marker in ['×', 'x', '*'] {
        for (i, _) in lc.match_indices(marker) {
            let rest = &lc[i + marker.len_utf8()..];
            let num: String = rest.chars().take_while(|c| c.is_ascii_digit() || *c == '.').collect();
            if let Ok(v) = num.parse::<f32>() {
                // 防误判：要求倍率符号前是空白/分隔符或开头
                let before = lc[..i].chars().last();
                if before.map(|c| !c.is_alphanumeric()).unwrap_or(true) && v > 0.0 && v <= 25.0 {
                    return (v * 10.0).round() as u8;
                }
            }
        }
    }
    0
}

/// §15.h：名字含 4K / UHD / 8K（仅 ASCII 不区分大小写；开尔文符号 U+212A、全角不算）视为支持 4K。
pub fn is_uhd(name: &str) -> bool {
    is_uhd_lower(&name.to_ascii_lowercase())
}

/// 已小写的名字或名称词元。
pub fn is_uhd_lower(lc: &str) -> bool {
    ["4k", "uhd", "8k"].iter().any(|k| lc.contains(k))
}

pub fn parse_tag(name: &str) -> Option<String> {
    let up = name.to_uppercase();
    TAGS.iter().find(|t| up.contains(&t.to_uppercase())).map(|t| t.to_string())
}

/// 解析 YAML，返回节点与被跳过的条目数（无 server/port、信息节点如"剩余流量"）。
pub fn parse_proxies_yaml(yaml: &str, subscription: u16) -> Result<(Vec<NodeInput>, u64), MobileError> {
    let v: serde_yaml::Value = serde_yaml::from_str(yaml).map_err(|e| MobileError::SubscriptionInvalid(e.to_string()))?;
    let list = v.get("proxies").and_then(|p| p.as_sequence()).ok_or_else(|| MobileError::SubscriptionInvalid("缺少 proxies".into()))?;
    let mut out = Vec::with_capacity(list.len());
    let mut skipped = 0;
    for p in list {
        let name = p.get("name").and_then(|x| x.as_str()).unwrap_or("").trim().to_string();
        let server = p.get("server").and_then(|x| x.as_str()).unwrap_or("").trim().to_string();
        let port = p.get("port").and_then(|x| x.as_u64().or_else(|| x.as_str().and_then(|s| s.parse().ok()))).unwrap_or(0);
        let protocol = p.get("type").and_then(|x| x.as_str()).unwrap_or("").to_string();
        let info = ["剩余", "到期", "过期", "官网", "expire", "traffic"].iter().any(|k| name.to_lowercase().contains(k));
        if name.is_empty() || server.is_empty() || port == 0 || port > 65535 || protocol.is_empty() || info {
            skipped += 1;
            continue;
        }
        out.push(NodeInput {
            region: crate::regions::infer(&name),
            tag: parse_tag(&name),
            multiplier_x10: parse_multiplier(&name),
            name,
            server,
            port: port as u16,
            protocol: normalize_protocol(&protocol),
            city: None,
            carrier: None,
            subscription,
        });
    }
    Ok((out, skipped))
}

pub(crate) fn normalize_protocol(t: &str) -> String {
    match t.to_ascii_lowercase().as_str() {
        "vless" => "VLESS",
        "vmess" => "VMess",
        "hysteria2" | "hy2" => "Hy2",
        "hysteria" => "Hysteria",
        "tuic" => "TUIC",
        "ss" | "shadowsocks" => "SS",
        "ssr" => "SSR",
        "trojan" => "Trojan",
        "wireguard" | "wg" => "WireGuard",
        "anytls" => "AnyTLS",
        "snell" => "Snell",
        "http" => "HTTP",
        "socks5" => "SOCKS5",
        other => return other.to_string(),
    }
    .to_string()
}

#[cfg(test)]
mod tests {

    /// contract/fixtures/uhd-names-v1.json：§15.h 4K 名字判定共享样本，两端 Mock 应逐条比对。
    /// 同时校验整名判定（NodeRow.uhd）与名称词元判定（uhd_bitmap）口径一致。
    #[test]
    fn uhd_fixtures() {
        let doc: serde_json::Value = serde_json::from_str(include_str!("../../contract/fixtures/uhd-names-v1.json")).unwrap();
        let cases = doc["cases"].as_array().unwrap();
        assert!(cases.len() >= 10);
        for c in cases {
            let name = c["name"].as_str().unwrap();
            let want = c["uhd"].as_bool().unwrap();
            assert_eq!(is_uhd(name), want, "is_uhd({name:?})");
            let by_token = crate::nodes::name_tokens(name).iter().any(|t| is_uhd_lower(t));
            assert_eq!(by_token, want, "name_tokens({name:?})");
        }
    }
    use super::*;
    #[test]
    fn parses_clash_yaml() {
        let y = r#"
proxies:
  - { name: "剩余流量：12 GB", type: ss, server: a.com, port: 1 }
  - { name: "🇯🇵 东京 IPLC 03 ×1.5", type: vless, server: jp3.example.com, port: 443 }
  - name: 香港 HKT 01
    type: hysteria2
    server: hk1.example.com
    port: "8443"
  - { name: broken, type: ss }
"#;
        let (n, skipped) = parse_proxies_yaml(y, 3).unwrap();
        assert_eq!(skipped, 2);
        assert_eq!(n.len(), 2);
        assert_eq!(n[0].region, "JP");
        assert_eq!(n[0].tag.as_deref(), Some("IPLC"));
        assert_eq!(n[0].multiplier_x10, 15);
        assert_eq!(n[0].protocol, "VLESS");
        assert_eq!(n[1].region, "HK");
        assert_eq!(n[1].port, 8443);
        assert_eq!(n[1].protocol, "Hy2");
        assert_eq!(n[1].subscription, 3);
        assert_eq!(parse_multiplier("Seoul x2"), 20);
        assert_eq!(parse_multiplier("box2"), 0);
    }
}
