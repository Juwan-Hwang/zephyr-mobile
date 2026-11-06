//! 地区识别：从节点名推断 ISO 3166 代码。覆盖国旗 emoji、中文名、英文名/代码、常见城市。

const TABLE: &[(&str, &str, &[&str])] = &[
    ("US", "美国", &["美国", "united states", "usa", "los angeles", "洛杉矶", "圣何塞", "san jose", "西雅图", "seattle", "纽约", "new york", "达拉斯", "dallas", "硅谷", "芝加哥"]),
    ("JP", "日本", &["日本", "japan", "东京", "tokyo", "大阪", "osaka"]),
    ("HK", "香港", &["香港", "hong kong", "hongkong"]),
    ("SG", "新加坡", &["新加坡", "狮城", "singapore"]),
    ("TW", "台湾", &["台湾", "台灣", "taiwan", "台北", "taipei", "台中", "taichung", "新北", "彰化"]),
    ("KR", "韩国", &["韩国", "韓國", "korea", "首尔", "seoul", "春川"]),
    ("DE", "德国", &["德国", "germany", "法兰克福", "frankfurt", "柏林", "berlin"]),
    ("GB", "英国", &["英国", "united kingdom", "伦敦", "london", "曼彻斯特", "manchester"]),
    ("NL", "荷兰", &["荷兰", "netherlands", "阿姆斯特丹", "amsterdam"]),
    ("FR", "法国", &["法国", "france", "巴黎", "paris"]),
    ("CA", "加拿大", &["加拿大", "canada", "多伦多", "toronto", "温哥华", "vancouver"]),
    ("AU", "澳大利亚", &["澳大利亚", "澳洲", "australia", "悉尼", "sydney"]),
    ("ID", "印度尼西亚", &["印尼", "印度尼西亚", "indonesia"]),
    ("IN", "印度", &["印度", "india", "孟买", "mumbai"]),
    ("BR", "巴西", &["巴西", "brazil", "圣保罗", "sao paulo"]),
    ("TR", "土耳其", &["土耳其", "turkey", "türkiye", "伊斯坦布尔", "istanbul"]),
    ("RU", "俄罗斯", &["俄罗斯", "russia", "莫斯科", "moscow"]),
    ("MY", "马来西亚", &["马来西亚", "malaysia", "吉隆坡"]),
    ("TH", "泰国", &["泰国", "thailand", "曼谷"]),
    ("VN", "越南", &["越南", "vietnam"]),
    ("PH", "菲律宾", &["菲律宾", "philippines"]),
    ("AR", "阿根廷", &["阿根廷", "argentina"]),
    ("CN", "中国", &["中国", "china", "回国"]),
];

pub fn name_of(code: &str) -> Option<&'static str> {
    TABLE.iter().find(|(c, _, _)| c.eq_ignore_ascii_case(code)).map(|(_, n, _)| *n)
}

/// 国旗 emoji（两个区域指示符）→ 代码
fn flag(name: &str) -> Option<String> {
    let cs: Vec<char> = name.chars().collect();
    for w in cs.windows(2) {
        let a = w[0] as u32;
        let b = w[1] as u32;
        if (0x1F1E6..=0x1F1FF).contains(&a) && (0x1F1E6..=0x1F1FF).contains(&b) {
            let s: String = [char::from(b'A' + (a - 0x1F1E6) as u8), char::from(b'A' + (b - 0x1F1E6) as u8)].iter().collect();
            return Some(if s == "UK" { "GB".into() } else { s });
        }
    }
    None
}

pub fn infer(name: &str) -> String {
    if let Some(f) = flag(name) {
        return f;
    }
    let lc = name.to_lowercase();
    for (code, _, keys) in TABLE {
        if keys.iter().any(|k| lc.contains(k)) {
            return (*code).to_string();
        }
    }
    // 独立的两字母代码，如 "JP-01"、"[US] xx"
    for tok in lc.split(|c: char| !c.is_ascii_alphabetic()) {
        if tok.len() == 2 {
            let up = tok.to_ascii_uppercase();
            if TABLE.iter().any(|(c, _, _)| *c == up) || up == "UK" {
                return if up == "UK" { "GB".into() } else { up };
            }
        }
    }
    "ZZ".into()
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn infer_regions() {
        assert_eq!(infer("🇯🇵 东京 03"), "JP");
        assert_eq!(infer("🇬🇧 London"), "GB");
        assert_eq!(infer("香港 HKT IPLC 01"), "HK");
        assert_eq!(infer("US-Fixed-01"), "US");
        assert_eq!(infer("TW-Fixed-01"), "TW");
        assert_eq!(infer("Seattle 1"), "US");
        assert_eq!(infer("剩余流量：12G"), "ZZ");
        assert_eq!(infer("印度尼西亚 01"), "ID");
    }
}
