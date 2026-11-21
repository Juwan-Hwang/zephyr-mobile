//! 订阅拉取的 SSRF 判定（契约 §16.i）：联网在平台层，判定复用桌面 zephyr-core，两端同一口径。
//!
//! - `fetchTarget(url)`：联网前校验 URL，给出 host / port 以及"用户亲手输入的内网地址"标记
//!   （桌面同语义：用户明确输入的 `nas.local` / `192.168.1.2` / 单标签主机允许直连，但重定向只能回到它自己）。
//! - `isPublicFetchAddress(ip)`：DNS 解析结果是否为可直连的公网地址（私网 / 链路本地 / 保留段 / fake-ip 段都算否）。

use crate::error::MobileError;
use zephyr_core::config::subscription::{is_private_ip, validate_subscription_url_basic};

#[derive(Debug, Clone, PartialEq, Eq)]
#[cfg_attr(feature = "uniffi", derive(uniffi::Record))]
pub struct FetchTarget {
    /// 小写主机名或 IP 字面量（IPv6 不带方括号）
    pub host: String,
    pub port: u16,
    pub https: bool,
    /// 用户亲手输入的内网主机（私网字面量、.local/.lan 等内网后缀、单标签名）：允许，但解析结果不做公网校验，
    /// 重定向只能指向同一主机
    pub user_entered_private: bool,
}

/// 联网前校验订阅 URL（scheme 仅 http/https、必须有 host、无控制字符）；不合法 → `SubscriptionInvalid`。
#[cfg_attr(feature = "uniffi", uniffi::export)]
pub fn fetch_target(url: String) -> Result<FetchTarget, MobileError> {
    let (host, port, user_entered_private) = validate_subscription_url_basic(&url).map_err(MobileError::SubscriptionInvalid)?;
    let https = url.trim().get(..6).is_some_and(|p| p.eq_ignore_ascii_case("https:"));
    let host = host.trim_start_matches('[').trim_end_matches(']').to_ascii_lowercase();
    Ok(FetchTarget { host, port, https, user_entered_private })
}

/// DNS 解析出的地址是否可以直连拉取订阅。无法解析的字符串 → false。
#[cfg_attr(feature = "uniffi", uniffi::export)]
pub fn is_public_fetch_address(ip: String) -> bool {
    let s = ip.trim().trim_start_matches('[').trim_end_matches(']');
    s.parse::<std::net::IpAddr>().is_ok_and(|a| !is_private_ip(a))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn target_flags() {
        let t = fetch_target("https://Sub.Example.com/api?token=x".into()).unwrap();
        assert_eq!(t, FetchTarget { host: "sub.example.com".into(), port: 443, https: true, user_entered_private: false });
        let t = fetch_target("http://192.168.1.2:8080/s".into()).unwrap();
        assert_eq!((t.port, t.https, t.user_entered_private), (8080, false, true));
        assert!(fetch_target("http://nas.local/s".into()).unwrap().user_entered_private);
        assert!(fetch_target("http://router/s".into()).unwrap().user_entered_private, "单标签名");
        assert_eq!(fetch_target("https://[2001:db8::1]/s".into()).unwrap().host, "2001:db8::1");
        for bad in ["ftp://a.example/s", "http:/sub", "https://", "http://a\texample/s", "zephyr://import?url=x"] {
            assert!(matches!(fetch_target(bad.into()), Err(MobileError::SubscriptionInvalid(_))), "{bad}");
        }
    }

    #[test]
    fn public_addresses() {
        for ok in ["1.1.1.1", "104.16.0.1", "2606:4700::1111", "[2606:4700::1111]"] {
            assert!(is_public_fetch_address(ok.into()), "{ok}");
        }
        for bad in [
            "10.0.0.1",
            "127.0.0.1",
            "169.254.169.254",
            "172.16.0.1",
            "192.168.1.1",
            "100.64.0.1",
            "198.18.0.5",
            "0.0.0.0",
            "::1",
            "fe80::1",
            "fd00::1",
            "::ffff:192.168.1.1",
            "not-an-ip",
            "",
        ] {
            assert!(!is_public_fetch_address(bad.into()), "{bad}");
        }
    }
}
