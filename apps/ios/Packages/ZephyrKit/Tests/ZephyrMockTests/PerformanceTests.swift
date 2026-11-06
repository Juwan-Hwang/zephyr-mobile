import XCTest
import ZephyrKit
@testable import ZephyrMock

/// 规模约束：queryNodes 任意查询 < 5 ms；nodeRows 读 500 行 < 2 ms。取多次运行的中位数（去抖 CI 噪声）。
final class PerformanceTests: XCTestCase {

    func median(_ runs: Int = 15, _ body: () async throws -> Void) async rethrows -> Double {
        var ts: [Double] = []
        for _ in 0..<runs {
            let t0 = DispatchTime.now().uptimeNanoseconds
            try await body()
            ts.append(Double(DispatchTime.now().uptimeNanoseconds - t0) / 1e6)
        }
        return ts.sorted()[ts.count / 2]
    }

    static let queries = ["", "jp", "日本", "东京", "ntt", "iplc", "东京 iplc", "us 家宽", "hkt", "香港 hkt bgp", "ip", "zzz",
                          "新加坡", "cn2 gia", "tw hinet 原生", "美国 洛杉矶", "sg singtel iepl", "大阪 softbank 原生",
                          "lg u+", "türk", "伦敦 bt", "de hetzner bgp", "x", "jp hkt", "So-net", "家宽 iplc"]

    func testQueryUnder5ms() async throws {
        let e = MockEngine(clock: .frozen941)
        var worst = 0.0
        defer { print("[perf] queryNodes worst median = \(worst) ms") }
        for q in Self.queries {
            _ = try await e.queryNodes(query: q) // 预热
            let ms = try await median { _ = try await e.queryNodes(query: q) }
            worst = max(worst, ms)
            XCTAssertLessThan(ms, 5, "queryNodes(“\(q)”) = \(ms) ms")
        }
    }

    func testNodeRows500Under2ms() async throws {
        let e = MockEngine(clock: .frozen941)
        var worst = 0.0
        defer { print("[perf] nodeRows(500) worst median = \(worst) ms") }
        for q in ["", "东京 iplc", "iplc", "tw hinet 原生"] {
            let r = try await e.queryNodes(query: q)
            for off in [Int64(0), r.total / 2, max(0, r.total - 500)] {
                _ = try await e.nodeRows(token: r.token, offset: off, limit: 500)
                let ms = try await median {
                    let p = try await e.nodeRows(token: r.token, offset: off, limit: 500)
                    precondition(p.rows.count == min(500, Int(r.total - off)))
                }
                worst = max(worst, ms)
                XCTAssertLessThan(ms, 2, "nodeRows(“\(q)”, \(off)) = \(ms) ms")
            }
        }
    }
}
