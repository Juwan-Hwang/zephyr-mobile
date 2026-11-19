// 指令输入的 token 化（仅用于展示：输入框下划线 + "服务 / 地区 / 范围 / 操作"卡片）。
// 规则移植自原型 index.html 的 parse()（SVC / RGN / ACT 词表），另加契约 §16.d U25 登记的多语言别名（两端共用）。
// 解析结果交给 CommandPlanner 出预览卡（§16.d）；引擎 commandSuggestions 只补充其余结果行。
// 纯 Swift，便于单测（Tests/ZephyrFeaturesTests/CommandTokenizerTests.swift）。

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
    /// 应用目录 id（契约 §10：chatgpt / claude …），AI / 视频服务才有；`setSceneException` 用。
    var appId: String?
    /// “其他”范围服务的直连域名（§16.d：GitHub = github.com、Telegram = telegram.org）。
    var host: String?
    var isEmpty: Bool { tokens.isEmpty }
    /// 只识别出场景词（“视频 / 流媒体”），没有具体服务：整场景操作。
    var isSceneWord: Bool { serviceName == nil && tokens.contains { $0.kind == .scene } }
    /// 识别出“直连”操作。
    var wantsDirect: Bool { tokens.contains { $0.kind == .action && $0.value == "直连" } }
    /// 识别出“4K”操作（契约 §15.h 场景节点过滤）。
    var wantsUHD: Bool { tokens.contains { $0.kind == .action && $0.value == "4K" } }
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
    /// 显示名 → 应用目录 id（契约 §10 内置应用目录）。
    static let appIds: [String: String] = ["GPT": "chatgpt", "Claude": "claude", "Gemini": "gemini",
                                           "Netflix": "netflix", "YouTube": "youtube", "Disney+": "disney"]
    /// 显示名 → 直连域名（契约 §16.d，只有“其他”范围的服务）。
    static let hosts: [String: String] = ["GitHub": "github.com", "Telegram": "telegram.org"]
    /// (显示名, 地区码, 关键词)
    /// 原型 RGN + 契约 §16.d U25 别名表（ar / fa / ur；KR / DE 为原型外地区）。新增别名先改契约表。
    static let regions: [(String, String, [String])] = [
        ("日本", "JP", ["日本", "东京", "大阪", "jp", "japan", "tokyo", "اليابان", "طوكيو", "ژاپن", "توکیو", "جاپان", "ٹوکیو"]),
        ("美国", "US", ["美国", "洛杉矶", "us", "usa", "الولايات المتحدة", "أمريكا", "آمریکا", "امریکا", "امریکہ"]),
        ("香港", "HK", ["香港", "hk", "هونغ كونغ", "هنگ کنگ", "ہانگ کانگ"]),
        ("新加坡", "SG", ["新加坡", "狮城", "sg", "سنغافورة", "سنگاپور"]),
        ("台湾", "TW", ["台湾", "台北", "tw", "تايوان", "تایوان", "تائیوان"]),
        ("英国", "GB", ["英国", "伦敦", "uk", "gb", "المملكة المتحدة", "بريطانيا", "بریتانیا", "انگلیس", "برطانیہ"]),
        ("韩国", "KR", ["韩国", "首尔", "kr", "كوريا", "کره", "کوریا"]),
        ("德国", "DE", ["德国", "法兰克福", "de", "ألمانيا", "آلمان", "جرمنی"]),
    ]
    static let actions: [(String, [String])] = [("直连", ["直连", "不走代理", "direct", "مباشر", "مستقیم", "براہ راست"]), ("4K", ["4k"])]
    /// 场景词（原型 /视频|流媒体/ + §16.d U25 别名），取输入里最靠前的一处。
    static let sceneWords: [String] = ["视频", "流媒体", "الفيديو", "فيديو", "ویدیو", "ویڈیو"]

    static func parse(_ input: String) -> CommandParse {
        let lower = Array(input.lowercased())
        var out = CommandParse(tokens: [])

        func isAsciiLetter(_ i: Int) -> Bool {
            guard i >= 0, i < lower.count else { return false }
            return lower[i].isASCII && lower[i].isLetter
        }
        /// 第一个满足 accept 的出现位置（默认任意位置）。
        func find(_ key: String, accept: (Range<Int>) -> Bool = { _ in true }) -> Range<Int>? {
            let k = Array(key)
            guard !k.isEmpty, k.count <= lower.count else { return nil }
            for i in 0...(lower.count - k.count) where Array(lower[i..<(i + k.count)]) == k {
                let r = i..<(i + k.count)
                if accept(r) { return r }
            }
            return nil
        }
        /// 两个字母的码（jp / us）必须是独立单词，避免 "gpt" 里的 "pt"、"plus" 里的 "us"；
        /// 跳过嵌在单词里的出现，继续找后面独立的那一处（"disney plus us" → 美国）。
        func standalone(_ key: String) -> (Range<Int>) -> Bool {
            guard key.count <= 2 else { return { _ in true } }
            return { r in !isAsciiLetter(r.lowerBound - 1) && !isAsciiLetter(r.upperBound) }
        }

        svc: for s in services {
            for k in s.1 {
                if let r = find(k, accept: standalone(k)) {
                    out.tokens.append(CommandToken(kind: .service, value: s.0, range: r))
                    out.serviceName = s.0; out.sceneId = s.3
                    out.appId = appIds[s.0]; out.host = hosts[s.0]
                    out.tokens.append(CommandToken(kind: .scope, value: s.2, range: nil))
                    break svc
                }
            }
        }
        rg: for g in regions {
            for k in g.2 {
                guard let r = find(k, accept: standalone(k)) else { continue }
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
        if out.serviceName == nil, let r = sceneWords.compactMap({ find($0) }).min(by: { $0.lowerBound < $1.lowerBound }) {
            out.tokens.insert(CommandToken(kind: .scene, value: "视频", range: r), at: 0)
            out.sceneId = "video"
        }
        // 展示顺序：服务/场景 → 地区 → 操作 → 范围（与原型一致）
        let order: [CommandToken.Kind] = [.service, .scene, .region, .action, .scope]
        out.tokens.sort { order.firstIndex(of: $0.kind)! < order.firstIndex(of: $1.kind)! }
        return out
    }
}
