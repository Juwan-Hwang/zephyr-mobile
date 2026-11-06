// 指令输入的 token 化（仅用于展示：输入框下划线 + "服务 / 地区 / 范围 / 操作"卡片）。
// 规则移植自原型 index.html 的 parse()（SVC / RGN / ACT 词表）。真正执行什么由引擎的 commandSuggestions 决定。
// 纯 Swift，便于单测。

import Foundation

struct CommandToken: Hashable, Sendable {
    enum Kind: String, Sendable { case service = "服务", region = "地区", scope = "范围", action = "操作", scene = "场景" }
    var kind: Kind
    var value: String
    /// 在原输入中的范围（UTF-16 偏移无关，按 Character 下标），用于下划线。范围 token 没有位置。
    var range: Range<Int>?
}

struct CommandParse: Hashable, Sendable {
    var tokens: [CommandToken]
    /// 服务所属场景 id（ai / video / other），用于把 switch_node 落到正确场景。
    var sceneId: String?
    var serviceName: String?
    var regionName: String?
    var regionCode: String?
    var isEmpty: Bool { tokens.isEmpty }
}

enum CommandTokenizer {
    /// (显示名, 关键词, 场景名, 场景 id)
    static let services: [(String, [String], String, String)] = [
        ("GPT", ["chatgpt", "gpt", "openai"], "AI", "ai"),
        ("Claude", ["claude", "anthropic"], "AI", "ai"),
        ("Gemini", ["gemini", "谷歌ai"], "AI", "ai"),
        ("Netflix", ["netflix", "奈飞", "网飞"], "视频", "video"),
        ("YouTube", ["youtube", "油管"], "视频", "video"),
        ("Disney+", ["disney+", "disney", "迪士尼"], "视频", "video"),
        ("GitHub", ["github"], "其他", "other"),
        ("Telegram", ["telegram", "电报", "tg"], "其他", "other"),
    ]
    /// (显示名, 地区码, 关键词)
    static let regions: [(String, String, [String])] = [
        ("日本", "JP", ["日本", "东京", "大阪", "jp", "japan", "tokyo"]),
        ("美国", "US", ["美国", "洛杉矶", "us", "usa"]),
        ("香港", "HK", ["香港", "hk"]),
        ("新加坡", "SG", ["新加坡", "狮城", "sg"]),
        ("台湾", "TW", ["台湾", "台北", "tw"]),
        ("英国", "GB", ["英国", "伦敦", "uk", "gb"]),
    ]
    static let actions: [(String, [String])] = [("直连", ["直连", "不走代理", "direct"]), ("4K", ["4k"])]

    static func parse(_ input: String) -> CommandParse {
        let lower = Array(input.lowercased())
        var out = CommandParse(tokens: [])

        func find(_ key: String) -> Range<Int>? {
            let k = Array(key)
            guard !k.isEmpty, k.count <= lower.count else { return nil }
            for i in 0...(lower.count - k.count) where Array(lower[i..<(i + k.count)]) == k {
                return i..<(i + k.count)
            }
            return nil
        }
        func isAsciiLetter(_ i: Int) -> Bool {
            guard i >= 0, i < lower.count else { return false }
            return lower[i].isASCII && lower[i].isLetter
        }

        svc: for s in services {
            for k in s.1 {
                if let r = find(k) {
                    out.tokens.append(CommandToken(kind: .service, value: s.0, range: r))
                    out.serviceName = s.0; out.sceneId = s.3
                    out.tokens.append(CommandToken(kind: .scope, value: s.2, range: nil))
                    break svc
                }
            }
        }
        rg: for g in regions {
            for k in g.2 {
                guard let r = find(k) else { continue }
                // 两个字母的码（jp / us）必须是独立单词，避免 "gpt" 里的 "pt"、"youtube" 里的 "us"
                if k.count <= 2, isAsciiLetter(r.lowerBound - 1) || isAsciiLetter(r.upperBound) { continue }
                out.tokens.append(CommandToken(kind: .region, value: g.0, range: r))
                out.regionName = g.0; out.regionCode = g.1
                break rg
            }
        }
        act: for a in actions {
            for k in a.1 {
                if let r = find(k) {
                    out.tokens.append(CommandToken(kind: .action, value: a.0, range: r))
                    break act
                }
            }
        }
        if out.serviceName == nil, let r = find("视频") ?? find("流媒体") {
            out.tokens.insert(CommandToken(kind: .scene, value: "视频", range: r), at: 0)
            out.sceneId = "video"
        }
        // 展示顺序：服务/场景 → 地区 → 操作 → 范围（与原型一致）
        let order: [CommandToken.Kind] = [.service, .scene, .region, .action, .scope]
        out.tokens.sort { order.firstIndex(of: $0.kind)! < order.firstIndex(of: $1.kind)! }
        return out
    }
}
