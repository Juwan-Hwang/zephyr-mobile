//! 错误详情脱敏（contract §22.b，U27 修订）：平台把 `ZephyrError.message` / 内核日志尾部显示在
//! 折叠的「错误详情」里之前，统一经这里处理，三端结果一致。

use crate::subs::redact_url;

/// 详情最多显示的字符数（按 Unicode 标量计，超出截断并加 `…`）。
pub const MAX_DIAGNOSTIC_CHARS: usize = 240;

fn is_url_end(c: char) -> bool {
    c.is_whitespace() || matches!(c, '"' | '\'' | '<' | '>' | '`' | '）' | '」' | '，' | '。')
}

/// 折叠空白；`http://` / `https://` 开头的 URL 换成 `redactUrl` 的脱敏形式（去掉 token、路径与凭据）；
/// 截断到 240 字。返回可直接显示的文本（仍不本地化，只作补充说明，标题照旧按 code 本地化）。
#[cfg_attr(feature = "uniffi", uniffi::export)]
pub fn redact_diagnostic(text: String) -> String {
    let collapsed = text.split_whitespace().collect::<Vec<_>>().join(" ");
    let mut out = String::with_capacity(collapsed.len());
    let mut rest = collapsed.as_str();
    loop {
        let next = ["https://", "http://"].iter().filter_map(|p| rest.find(p)).min();
        match next {
            Some(i) => {
                out.push_str(&rest[..i]);
                let tail = &rest[i..];
                let end = tail.find(is_url_end).unwrap_or(tail.len());
                out.push_str(&redact_url(&tail[..end]));
                rest = &tail[end..];
            }
            None => {
                out.push_str(rest);
                break;
            }
        }
    }
    if out.chars().count() > MAX_DIAGNOSTIC_CHARS {
        let mut t: String = out.chars().take(MAX_DIAGNOSTIC_CHARS).collect();
        t.push('…');
        t
    } else {
        out
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn redacts_urls_collapses_and_truncates() {
        let r = redact_diagnostic("fetch  failed:\n https://user:pw@sub.example.com/api/subscribe?token=SECRET （超时）".into());
        assert!(!r.contains("SECRET") && !r.contains("pw") && !r.contains("subscribe"), "{r}");
        assert!(r.starts_with("fetch failed: https://") && r.ends_with("（超时）"), "{r}");
        assert!(!r.contains('\n') && !r.contains("  "));
        assert_eq!(redact_diagnostic("geodata missing: GeoSite.dat".into()), "geodata missing: GeoSite.dat");
        let long = redact_diagnostic("错".repeat(300));
        assert_eq!(long.chars().count(), MAX_DIAGNOSTIC_CHARS + 1);
        assert!(long.ends_with('…'));
        assert_eq!(redact_diagnostic(String::new()), "");
    }
}
