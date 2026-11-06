// 节点库确定性生成 —— 逐行移植 design/prototype/pages.js（contract/mock-spec.md §1–§2）。
// 全部 32 位无符号运算；结果与 contract/fixtures/mock-v0.json 逐项一致（见 ZephyrMockTests）。

import ZephyrKit

public struct MockRegion: Sendable, Hashable {
    public let code: String
    public let name: String
    public let count: Int64
    public let cities: [String]
    public let baseLatency: Int32
    public let carriers: [String]
    /// lcm(cities.count, 5 * carriers.count)，nodeName 的编号周期。
    let namePeriod: Int64
}

public enum MockNodes {

    /// 地区表 RG，顺序固定（index 0..14）。
    public static let regions: [MockRegion] = {
        let raw: [(String, String, Int64, [String], Int32, [String])] = [
            ("US", "美国", 3118402, ["洛杉矶", "圣何塞", "西雅图", "纽约", "达拉斯"], 152, ["CN2 GIA", "Cogent", "Zenlayer", "HE"]),
            ("JP", "日本", 2204117, ["东京", "大阪"], 58, ["NTT", "IIJ", "KDDI", "SoftBank"]),
            ("HK", "香港", 1906551, ["香港"], 34, ["HKT", "HKBN", "PCCW", "CMI"]),
            ("SG", "新加坡", 1512880, ["新加坡"], 63, ["Akari", "SingTel", "StarHub"]),
            ("TW", "台湾", 1288406, ["台北", "台中"], 41, ["HiNet", "Seednet", "So-net"]),
            ("KR", "韩国", 702315, ["首尔", "春川"], 69, ["KT", "SK", "LG U+"]),
            ("DE", "德国", 488210, ["法兰克福", "柏林"], 204, ["Hetzner", "DTAG"]),
            ("GB", "英国", 455903, ["伦敦", "曼彻斯特"], 218, ["BT", "Vultr"]),
            ("NL", "荷兰", 301442, ["阿姆斯特丹"], 226, ["KPN", "Leaseweb"]),
            ("FR", "法国", 254118, ["巴黎"], 231, ["OVH", "Orange"]),
            ("CA", "加拿大", 239770, ["多伦多", "温哥华"], 171, ["Bell", "Rogers"]),
            ("AU", "澳大利亚", 214906, ["悉尼"], 139, ["Telstra", "Optus"]),
            ("IN", "印度", 198331, ["孟买"], 118, ["Jio", "Airtel"]),
            ("BR", "巴西", 126004, ["圣保罗"], 301, ["Vivo", "Claro"]),
            ("TR", "土耳其", 98447, ["伊斯坦布尔"], 246, ["Türk Telekom"]),
        ]
        return raw.map { r in
            MockRegion(code: r.0, name: r.1, count: r.2, cities: r.3, baseLatency: r.4, carriers: r.5,
                       namePeriod: lcm(Int64(r.3.count), Int64(5 * r.5.count)))
        }
    }()

    /// 13,109,802
    public static let total: Int64 = regions.reduce(0) { $0 + $1.count }
    public static let tags = ["IPLC", "IEPL", "BGP", "家宽", "原生"]
    public static let protocols = ["VLESS", "Hy2", "TUIC", "SS", "Trojan"]
    static let mult = ["", "", "", "", " ×1.5", "", "", " ×0.5", "", " ×2"]
    static let multValue: [Float?] = [nil, nil, nil, nil, 1.5, nil, nil, 0.5, nil, 2]
    /// 原型"已检测 41,280"的基数。
    public static let testedBase: Int64 = 41_280
    public static let idStride: UInt64 = 100_000_000

    // MARK: 哈希与属性

    /// hsh(r, j)：与 JS `(j*2654435761+r*97)>>>0; h^=h>>>15; h=Math.imul(h,2246822519)>>>0; h^=h>>>13` 位级一致。
    @inline(__always)
    public static func hsh(_ r: Int64, _ j: Int64) -> UInt32 {
        let a = UInt64(bitPattern: j) &* 2654435761 &+ UInt64(bitPattern: r) &* 97
        var h = UInt32(truncatingIfNeeded: a)
        h ^= h >> 15
        h = h &* 2246822519          // imul 取低 32 位 == 无符号环绕乘法
        h ^= h >> 13
        return h
    }

    @inline(__always) public static func tagOf(_ r: Int, _ j: Int64) -> Int { Int((j * 7 + Int64(r)) % 5) }
    @inline(__always) public static func protOf(_ r: Int, _ j: Int64) -> Int { Int(hsh(Int64(r) + 7, j) % 5) }
    @inline(__always) public static func carOf(_ r: Int, _ j: Int64) -> Int { Int((j / 5) % Int64(regions[r].carriers.count)) }
    @inline(__always) public static func cityOf(_ r: Int, _ j: Int64) -> Int { Int(j % Int64(regions[r].cities.count)) }
    @inline(__always) static func multIndex(_ r: Int, _ j: Int64) -> Int { Int(hsh(Int64(r) + 3, j) % 10) }

    public static func nodeName(_ r: Int, _ j: Int64) -> String {
        let g = regions[r]
        let n = (j / g.namePeriod) % 64 + 1
        let nn = n < 10 ? "0\(n)" : "\(n)"
        return "\(g.cities[cityOf(r, j)]) \(g.carriers[carOf(r, j)]) \(tags[tagOf(r, j)]) \(nn)\(mult[multIndex(r, j)])"
    }

    /// 缓存延迟：h % 11 < 3 → baseLatency + h % 37，否则 nil。
    public static func cachedLatency(_ r: Int, _ j: Int64) -> Int32? {
        let h = hsh(Int64(r), j)
        return h % 11 < 3 ? regions[r].baseLatency + Int32(h % 37) : nil
    }

    /// testLatency 的测得值（mock-spec §6）：缓存值优先；hsh % 23 == 0 记超时 -1；否则 base + hsh % 37。
    public static func measuredLatency(_ r: Int, _ j: Int64) -> Int32 {
        if let c = cachedLatency(r, j) { return c }
        let h = hsh(Int64(r), j)
        if h % 23 == 0 { return -1 }
        return regions[r].baseLatency + Int32(h % 37)
    }

    // MARK: ID

    @inline(__always) public static func id(_ r: Int, _ j: Int64) -> NodeId { UInt64(r) * idStride + UInt64(j) }

    /// 拆出 (region, index)；不是生成节点返回 nil。
    public static func split(_ id: NodeId) -> (r: Int, j: Int64)? {
        let r = Int(id / idStride), j = Int64(id % idStride)
        guard r < regions.count, j < regions[r].count else { return nil }
        return (r, j)
    }

    public static func regionIndex(code: String) -> Int? { regions.firstIndex { $0.code == code.uppercased() } }

    public static func summary(_ r: Int, _ j: Int64, latency: Int32?) -> NodeSummary {
        let g = regions[r]
        return NodeSummary(id: id(r, j), name: nodeName(r, j), region: g.code, city: g.cities[cityOf(r, j)],
                           carrier: g.carriers[carOf(r, j)], tag: tags[tagOf(r, j)], protocol: protocols[protOf(r, j)],
                           multiplier: multValue[multIndex(r, j)], latencyMs: latency)
    }

    static func gcd(_ a: Int64, _ b: Int64) -> Int64 { b == 0 ? a : gcd(b, a % b) }
    static func lcm(_ a: Int64, _ b: Int64) -> Int64 { a / gcd(a, b) * b }
}
