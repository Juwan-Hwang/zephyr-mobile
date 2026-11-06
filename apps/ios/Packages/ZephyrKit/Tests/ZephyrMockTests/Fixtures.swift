import Foundation

/// contract/fixtures/mock-v0.json（用 #filePath 定位仓库根）。
enum Fixtures {
    static let repoRoot: URL = {
        var u = URL(fileURLWithPath: #filePath)
        for _ in 0..<7 { u.deleteLastPathComponent() }   // Tests/ZephyrMockTests/F.swift → repo
        return u
    }()
    static let url = repoRoot.appendingPathComponent("contract/fixtures/mock-v0.json")
    nonisolated(unsafe) static let json: [String: Any] = {
        let data = try! Data(contentsOf: url)
        return try! JSONSerialization.jsonObject(with: data) as! [String: Any]
    }()
    static var regions: [[String: Any]] { json["regions"] as! [[String: Any]] }
    static var nodes: [[String: Any]] { json["nodes"] as! [[String: Any]] }
    static var queries: [[String: Any]] { json["queries"] as! [[String: Any]] }
    static var rules: [String: Any] { json["rules"] as! [String: Any] }
}

extension Dictionary where Key == String, Value == Any {
    func int(_ k: String) -> Int64? { (self[k] as? NSNumber)?.int64Value }
    func str(_ k: String) -> String? { self[k] as? String }
}
