// zephyr:// 深链解析。纯函数，便于单测与 App Intents / 小组件复用。
//
//   zephyr://home                         回到首页（关闭浮层、清空 path）
//   zephyr://connect | disconnect | toggle
//   zephyr://mode/rule | global | direct
//   zephyr://scene/<id>                   场景详情
//   zephyr://connections[/<host>]         最近连接 / 某个域名的连接轨迹
//   zephyr://command?q=<text>             打开指令并预填
//   zephyr://today                        今日卡片
//   zephyr://library                      资料库
//   zephyr://nodes?q=<text>               节点页
//   zephyr://rules?q=<text>               规则页
//   zephyr://subscriptions | settings

import Foundation

public enum DeepLink: Hashable, Sendable {
    case home
    case connect, disconnect, toggle
    case mode(String)
    case sheet(SheetRoute)
    case command(String)
    case push(Route)

    public static let scheme = "zephyr"

    public init?(url: URL) {
        guard url.scheme?.lowercased() == Self.scheme else { return nil }
        let comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let q = comps?.queryItems?.first(where: { $0.name == "q" })?.value
        // zephyr://scene/ai → host = scene, path = /ai
        let head = (url.host ?? "").lowercased()
        let rest = url.pathComponents.filter { $0 != "/" }
        let arg = rest.first

        switch head {
        case "", "home": self = .home
        case "connect": self = .connect
        case "disconnect": self = .disconnect
        case "toggle": self = .toggle
        case "mode":
            guard let m = arg?.lowercased(), ["rule", "global", "direct"].contains(m) else { return nil }
            self = .mode(m)
        case "scene":
            guard let id = arg, !id.isEmpty else { return nil }
            self = .sheet(.scene(id: id))
        case "connections": self = .sheet(.connections(traceID: arg))
        case "today": self = .sheet(.today)
        case "library": self = .sheet(.library)
        case "command": self = .command(q ?? "")
        case "nodes": self = .push(.nodes(query: q ?? ""))
        case "rules": self = .push(.rules(query: q))
        case "subscriptions": self = .push(.subscriptions)
        case "settings": self = .push(.settings)
        default: return nil
        }
    }

    /// 反向生成 URL（小组件 / 实时活动的 widgetURL 用）。
    public var url: URL {
        var c = URLComponents()
        c.scheme = Self.scheme
        switch self {
        case .home: c.host = "home"
        case .connect: c.host = "connect"
        case .disconnect: c.host = "disconnect"
        case .toggle: c.host = "toggle"
        case .mode(let m): c.host = "mode"; c.path = "/\(m)"
        case .command(let t): c.host = "command"; if !t.isEmpty { c.percentEncodedQueryItems = [Self.q(t)] }
        case .sheet(let s):
            switch s {
            case .library: c.host = "library"
            case .today: c.host = "today"
            case .scene(let id): c.host = "scene"; c.path = "/\(id)"
            case .connections(let t): c.host = "connections"; if let t { c.path = "/\(t)" }
            }
        case .push(let r):
            switch r {
            case .nodes(let q): c.host = "nodes"; if !q.isEmpty { c.percentEncodedQueryItems = [Self.q(q)] }
            case .rules(let q): c.host = "rules"; if let q { c.percentEncodedQueryItems = [Self.q(q)] }
            case .subscriptions: c.host = "subscriptions"
            case .settings: c.host = "settings"
            }
        }
        return c.url ?? URL(string: "zephyr://home")!
    }

    /// `queryItems` 不会转义 `&`、`=`、`+`（它们在 query 里合法），"a&b=c" 会被读回成 "a"。
    /// 这里先按严格字符集转义，再用 percentEncodedQueryItems 原样放入。
    private static let queryValueAllowed: CharacterSet = {
        var s = CharacterSet.urlQueryAllowed
        s.remove(charactersIn: "&=+?#")
        return s
    }()

    private static func q(_ value: String) -> URLQueryItem {
        URLQueryItem(name: "q", value: value.addingPercentEncoding(withAllowedCharacters: queryValueAllowed) ?? value)
    }
}
