//! 原型数据生成器的 Rust 移植（contract/mock-spec.md §1–2），用于基准测试与 fixtures 一致性校验。

pub struct RegionSpec {
    pub code: &'static str,
    pub name: &'static str,
    pub count: u32,
    pub cities: &'static [&'static str],
    pub base_latency: u32,
    pub carriers: &'static [&'static str],
}

pub const RG: &[RegionSpec] = &[
    RegionSpec { code: "US", name: "美国", count: 3118402, cities: &["洛杉矶", "圣何塞", "西雅图", "纽约", "达拉斯"], base_latency: 152, carriers: &["CN2 GIA", "Cogent", "Zenlayer", "HE"] },
    RegionSpec { code: "JP", name: "日本", count: 2204117, cities: &["东京", "大阪"], base_latency: 58, carriers: &["NTT", "IIJ", "KDDI", "SoftBank"] },
    RegionSpec { code: "HK", name: "香港", count: 1906551, cities: &["香港"], base_latency: 34, carriers: &["HKT", "HKBN", "PCCW", "CMI"] },
    RegionSpec { code: "SG", name: "新加坡", count: 1512880, cities: &["新加坡"], base_latency: 63, carriers: &["Akari", "SingTel", "StarHub"] },
    RegionSpec { code: "TW", name: "台湾", count: 1288406, cities: &["台北", "台中"], base_latency: 41, carriers: &["HiNet", "Seednet", "So-net"] },
    RegionSpec { code: "KR", name: "韩国", count: 702315, cities: &["首尔", "春川"], base_latency: 69, carriers: &["KT", "SK", "LG U+"] },
    RegionSpec { code: "DE", name: "德国", count: 488210, cities: &["法兰克福", "柏林"], base_latency: 204, carriers: &["Hetzner", "DTAG"] },
    RegionSpec { code: "GB", name: "英国", count: 455903, cities: &["伦敦", "曼彻斯特"], base_latency: 218, carriers: &["BT", "Vultr"] },
    RegionSpec { code: "NL", name: "荷兰", count: 301442, cities: &["阿姆斯特丹"], base_latency: 226, carriers: &["KPN", "Leaseweb"] },
    RegionSpec { code: "FR", name: "法国", count: 254118, cities: &["巴黎"], base_latency: 231, carriers: &["OVH", "Orange"] },
    RegionSpec { code: "CA", name: "加拿大", count: 239770, cities: &["多伦多", "温哥华"], base_latency: 171, carriers: &["Bell", "Rogers"] },
    RegionSpec { code: "AU", name: "澳大利亚", count: 214906, cities: &["悉尼"], base_latency: 139, carriers: &["Telstra", "Optus"] },
    RegionSpec { code: "IN", name: "印度", count: 198331, cities: &["孟买"], base_latency: 118, carriers: &["Jio", "Airtel"] },
    RegionSpec { code: "BR", name: "巴西", count: 126004, cities: &["圣保罗"], base_latency: 301, carriers: &["Vivo", "Claro"] },
    RegionSpec { code: "TR", name: "土耳其", count: 98447, cities: &["伊斯坦布尔"], base_latency: 246, carriers: &["Türk Telekom"] },
];
pub const TAGS: [&str; 5] = ["IPLC", "IEPL", "BGP", "家宽", "原生"];
pub const PROT: [&str; 5] = ["VLESS", "Hy2", "TUIC", "SS", "Trojan"];
const MULT: [&str; 10] = ["", "", "", "", " ×1.5", "", "", " ×0.5", "", " ×2"];

pub fn hsh(r: u32, j: u32) -> u32 {
    let mut h = ((j as u64 * 2654435761 + r as u64 * 97) & 0xFFFF_FFFF) as u32;
    h ^= h >> 15;
    h = (h as i32).wrapping_mul(2246822519u32 as i32) as u32;
    h ^= h >> 13;
    h
}
pub fn tag_of(r: u32, j: u32) -> usize { ((j as u64 * 7 + r as u64) % 5) as usize }
pub fn prot_of(r: u32, j: u32) -> usize { (hsh(r + 7, j) % 5) as usize }
pub fn car_of(r: u32, j: u32) -> usize { ((j / 5) as usize) % RG[r as usize].carriers.len() }
fn gcd(a: u32, b: u32) -> u32 { if b == 0 { a } else { gcd(b, a % b) } }
fn lcm(a: u32, b: u32) -> u32 { a / gcd(a, b) * b }

pub fn node_name(r: u32, j: u32) -> String {
    let g = &RG[r as usize];
    let c = g.cities.len() as u32;
    let n = (j / lcm(c, 5 * g.carriers.len() as u32)) % 64 + 1;
    format!("{} {} {} {:02}{}", g.cities[(j % c) as usize], g.carriers[car_of(r, j)], TAGS[tag_of(r, j)], n, MULT[(hsh(r + 3, j) % 10) as usize])
}
pub fn cached_latency(r: u32, j: u32) -> Option<u32> {
    let h = hsh(r, j);
    (h % 11 < 3).then(|| RG[r as usize].base_latency + h % 37)
}
pub fn total() -> u64 { RG.iter().map(|g| g.count as u64).sum() }

/// 生成 NodeInput（server 用确定性假地址，保证指纹唯一）。scale ∈ (0,1] 按比例缩小每个地区。
pub fn nodes(scale: f64) -> impl Iterator<Item = crate::nodes::NodeInput> {
    RG.iter().enumerate().flat_map(move |(r, g)| {
        let n = ((g.count as f64) * scale).round().max(1.0) as u32;
        (0..n).map(move |j| {
            let r32 = r as u32;
            let mult = match (hsh(r32 + 3, j) % 10) as usize { 4 => 15, 7 => 5, 9 => 20, _ => 0 };
            crate::nodes::NodeInput {
                name: node_name(r32, j),
                server: format!("n{j}.{}.mock", g.code.to_ascii_lowercase()),
                port: 443,
                protocol: PROT[prot_of(r32, j)].to_string(),
                region: g.code.to_string(),
                city: Some(g.cities[(j as usize) % g.cities.len()].to_string()),
                carrier: Some(g.carriers[car_of(r32, j)].to_string()),
                tag: Some(TAGS[tag_of(r32, j)].to_string()),
                multiplier_x10: mult,
                subscription: 0,
            }
        })
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn matches_prototype_samples() {
        assert_eq!(total(), 13_109_802);
        // 来自 contract/fixtures/mock-v0.json（原型求值）
        let fx: serde_yaml::Value = serde_yaml::from_str(&std::fs::read_to_string(concat!(env!("CARGO_MANIFEST_DIR"), "/../contract/fixtures/mock-v0.json")).unwrap()).unwrap();
        let nodes = fx["nodes"].as_sequence().unwrap();
        assert!(nodes.len() > 200);
        for n in nodes {
            let r = n["region"].as_u64().unwrap() as u32;
            let j = n["index"].as_u64().unwrap() as u32;
            assert_eq!(node_name(r, j), n["name"].as_str().unwrap(), "name r={r} j={j}");
            assert_eq!(hsh(r, j) as u64, n["hash"].as_u64().unwrap());
            assert_eq!(cached_latency(r, j).map(|x| x as u64), n["cachedLatency"].as_u64());
        }
    }
}
