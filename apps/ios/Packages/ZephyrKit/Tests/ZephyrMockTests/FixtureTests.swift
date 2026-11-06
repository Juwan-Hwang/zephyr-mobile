import XCTest
import ZephyrKit
@testable import ZephyrMock

/// 与 contract/fixtures/mock-v0.json 逐项比对。
final class FixtureTests: XCTestCase {

    func testRegionsAndTotal() {
        XCTAssertEqual(Fixtures.json["total"] as? Int, 13_109_802)
        XCTAssertEqual(MockNodes.total, 13_109_802)
        XCTAssertEqual(Fixtures.regions.count, MockNodes.regions.count)
        for (i, f) in Fixtures.regions.enumerated() {
            let r = MockNodes.regions[i]
            XCTAssertEqual(f.int("index"), Int64(i))
            XCTAssertEqual(f.str("code"), r.code)
            XCTAssertEqual(f.str("name"), r.name)
            XCTAssertEqual(f.int("count"), r.count)
            XCTAssertEqual(f["cities"] as? [String], r.cities)
            XCTAssertEqual(f.int("baseLatency"), Int64(r.baseLatency))
            XCTAssertEqual(f["carriers"] as? [String], r.carriers)
        }
        XCTAssertEqual(Fixtures.json["tags"] as? [String], MockNodes.tags)
        XCTAssertEqual(Fixtures.json["protocols"] as? [String], MockNodes.protocols)
    }

    func testNodeSamples() async throws {
        let engine = MockEngine(clock: .frozen941)
        XCTAssertGreaterThan(Fixtures.nodes.count, 200)
        for f in Fixtures.nodes {
            let r = Int(f.int("region")!), j = f.int("index")!
            let id = UInt64(f.int("id")!)
            XCTAssertEqual(MockNodes.id(r, j), id)
            XCTAssertEqual(UInt64(MockNodes.hsh(Int64(r), j)), UInt64(f.int("hash")!), "hash \(id)")
            XCTAssertEqual(MockNodes.nodeName(r, j), f.str("name"), "name \(id)")
            let lat = MockNodes.cachedLatency(r, j)
            XCTAssertEqual(lat.map(Int64.init), f.int("cachedLatency"), "latency \(id)")
            let d = try await engine.node(id: id)
            XCTAssertEqual(d.summary.name, f.str("name"))
            XCTAssertEqual(d.summary.tag, f.str("tag"))
            XCTAssertEqual(d.summary.protocol, f.str("protocol"))
            XCTAssertEqual(d.summary.carrier, f.str("carrier"))
            XCTAssertEqual(d.summary.city, f.str("city"))
            XCTAssertEqual(d.summary.region, MockNodes.regions[r].code)
            XCTAssertEqual(d.summary.latencyMs.map(Int64.init), f.int("cachedLatency"))
        }
    }

    func testQueries() async throws {
        let engine = MockEngine(clock: .frozen941)
        XCTAssertEqual(Fixtures.queries.count, 16)
        for f in Fixtures.queries {
            let q = f.str("query")!
            let res = try await engine.queryNodes(query: q)
            XCTAssertEqual(res.total, f.int("total"), "total “\(q)”")
            let fs = f["sections"] as! [[String: Any]]
            XCTAssertEqual(res.sections.map(\.region), fs.map { $0.str("region")! }, "sections “\(q)”")
            XCTAssertEqual(res.sections.map(\.count), fs.map { $0.int("count")! }, "counts “\(q)”")
            XCTAssertEqual(res.rowCount, res.total + Int64(res.sections.count))

            // 前 12 行（含头行）：行号 → locate → nodeRows
            let expected = f["firstRows"] as! [[String: Any]]
            let page = try await engine.nodeRows(token: res.token, offset: 0, limit: 12)
            XCTAssertEqual(page.total, res.total)
            for (row, e) in expected.enumerated() {
                switch res.sections.locate(row: Int64(row)) {
                case .header(let s):
                    XCTAssertEqual(res.sections[s].region, e.str("header"), "row \(row) “\(q)”")
                case .node(_, _, let ordinal):
                    XCTAssertNil(e["header"], "row \(row) “\(q)” expected header")
                    let n = page.rows[Int(ordinal)]
                    XCTAssertEqual(n.id, UInt64(e.int("id") ?? -1), "row \(row) id “\(q)”")
                    XCTAssertEqual(n.name, e.str("name"), "row \(row) name “\(q)”")
                case nil:
                    XCTFail("row \(row) out of range “\(q)”")
                }
            }
        }
    }

    func testDeepRowsMatchModel() async throws {
        // 深处分页与 rowAt 映射一致：第 k 个 = floor(k/|S|)*P + S[k%|S|]
        let engine = MockEngine(clock: .frozen941)
        let res = try await engine.queryNodes(query: "东京 iplc")
        let page = try await engine.nodeRows(token: res.token, offset: 220_000, limit: 500)
        XCTAssertEqual(page.rows.count, Int(res.total - 220_000))
        for n in page.rows {
            XCTAssertTrue(n.name.hasPrefix("东京 "), n.name)
            XCTAssertEqual(n.tag, "IPLC")
        }
        let last = page.rows.last!
        let (r, j) = MockNodes.split(last.id)!
        XCTAssertEqual(r, 1); XCTAssertLessThan(j, MockNodes.regions[1].count)
        // 跨分区
        let all = try await engine.queryNodes(query: "iplc")
        let cross = try await engine.nodeRows(token: all.token, offset: all.sections[0].count - 2, limit: 5)
        XCTAssertEqual(cross.rows.map(\.region), ["US", "US", "JP", "JP", "JP"])
    }

    func testRules() async throws {
        let engine = MockEngine(clock: .frozen941)
        let stats = await engine.ruleStats()
        XCTAssertEqual(stats.total, 103_606_731)
        XCTAssertEqual(Fixtures.rules.int("total"), 103_606_731)
        XCTAssertEqual(stats.diskBytes, 1_900_000_000)
        XCTAssertTrue(stats.compiled)
        let kinds: [String: LayerKind] = ["覆写": .override, "订阅": .subscription, "域名": .domain, "IP": .ip]
        let fl = Fixtures.rules["layers"] as! [[String: Any]]
        XCTAssertEqual(stats.layers.count, fl.count)
        for (l, f) in zip(stats.layers, fl) {
            XCTAssertEqual(Int64(l.index), f.int("index"))
            XCTAssertEqual(l.kind, kinds[f.str("kind")!])
            XCTAssertEqual(l.name, f.str("name"))
            XCTAssertEqual(l.count, f.int("count"))
            XCTAssertEqual(l.note, f.str("note"))
        }
        let map = ["AI": "ai", "V": "video", "O": "other", "DIRECT": "DIRECT", "REJECT": "REJECT"]
        for t in Fixtures.rules["tests"] as! [[String: Any]] {
            let input = t.str("input")!
            let tr = try await engine.testRule(input: input)
            XCTAssertEqual(tr.layerIndex.map(Int64.init), t.int("layerIndex"), input)
            XCTAssertEqual(tr.rule, t.str("rule"), input)
            XCTAssertEqual(tr.ruleNo, t.int("ruleNo"), input)
            XCTAssertEqual(tr.policy, map[t.str("policy")!], input)
            XCTAssertEqual(tr.tookMicros, 10 + Int64(input.count))
            if ["ai", "video", "other"].contains(tr.policy) {
                XCTAssertEqual(tr.scene?.id, tr.policy); XCTAssertNotNil(tr.exitIp)
            } else { XCTAssertNil(tr.scene) }
        }
        let ip = try await engine.testRule(input: "8.8.8.8")
        XCTAssertTrue(ip.isIp)
        XCTAssertEqual(ip.exitIp, "198.51.100.41")
        do { _ = try await engine.testRule(input: "   "); XCTFail() } catch let e as ZephyrError { XCTAssertEqual(e.code, .ruleInputInvalid) }
    }
}
