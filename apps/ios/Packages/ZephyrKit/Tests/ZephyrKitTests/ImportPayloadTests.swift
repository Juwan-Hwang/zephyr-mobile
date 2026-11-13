// 契约 §15 导入载荷：Swift 实现与 contract/fixtures/import-payload-v1.json（核心单测同一份）逐条比对。

import Foundation
import XCTest
@testable import ZephyrKit

final class ImportPayloadTests: XCTestCase {
    private struct Fixture: Decodable {
        struct Case: Decodable {
            struct OK: Decodable {
                struct Item: Decodable { var name: String?; var url: String; var autoUpdateHours: Int32? }
                var kind: String
                var items: [Item]
            }
            var id: String
            var input: String
            var ok: OK?
            var err: String?
        }
        var version: Int
        var cases: [Case]
    }

    private static var fixtureURL: URL {
        var u = URL(fileURLWithPath: #filePath)
        for _ in 0..<7 { u.deleteLastPathComponent() }   // → 仓库根
        return u.appendingPathComponent("contract/fixtures/import-payload-v1.json")
    }

    func testMatchesContractFixtures() throws {
        let data = try Data(contentsOf: Self.fixtureURL)
        let fx = try JSONDecoder().decode(Fixture.self, from: data)
        XCTAssertEqual(fx.version, 1)
        XCTAssertFalse(fx.cases.isEmpty)
        for c in fx.cases {
            do {
                let r = try ParsedImport.parse(c.input)
                guard let ok = c.ok else { XCTFail("\(c.id)：应当失败（\(c.err ?? "")），却解析成 \(r)"); continue }
                XCTAssertEqual(r.kind.rawValue, ok.kind, c.id)
                XCTAssertEqual(r.items, ok.items.map { .init(name: $0.name, url: $0.url, autoUpdateHours: $0.autoUpdateHours) }, c.id)
            } catch let f as ParsedImport.Failure {
                XCTAssertEqual(f.category, c.err, "\(c.id)：\(f.message)")
            }
        }
    }

    func testEngineErrorWrapper() {
        XCTAssertThrowsError(try ParsedImport.parseOrThrowEngineError("hello")) { e in
            XCTAssertEqual((e as? ZephyrError)?.code, .subscriptionInvalid)
        }
    }

    func testLooksLikeConfig() {
        XCTAssertTrue(ParsedImport.looksLikeConfig("proxies:\n  - name: a"))
        XCTAssertFalse(ParsedImport.looksLikeConfig("https://a.example.com"))
    }
}
