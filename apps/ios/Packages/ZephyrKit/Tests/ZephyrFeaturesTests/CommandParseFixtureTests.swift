// 契约 §15.b 指令解析样本：CommandTokenizer 与 contract/fixtures/command-parse-v1.json 逐条比对（审计 #207 E40/E47）。
// 样本用 #filePath 定位仓库根读取（同 ImportPayloadTests / UHDFixtureTests），SwiftPM 与 CI 不依赖测试资源拷贝。
//
// 与样本的对应关系（只在比对时换算，不改变 iOS 的 token 结构）：
// - iOS 的 `.scope` token（“范围”卡片，无位置）不在样本 tokens 里；样本把范围单独放在 `scope` 字段。
//   比对时把 `.scope` 从 tokens 中分开，样本 `scope` 与 iOS 的 sceneId（ai/video/other → AI/视频/其他）比对。
// - iOS 在没有具体服务时把“视频 / 流媒体”记为 `.scene` token；样本里它是 kind=service、service=视频。
// - iOS 的下划线范围按 Character 下标，样本按 UTF-16 下标；样本均为 BMP 字符，两者相同，这里仍按 UTF-16 换算后比对。

import Foundation
import XCTest
@testable import ZephyrFeatures

final class CommandParseFixtureTests: XCTestCase {
    private struct Fixture: Decodable {
        struct Region: Decodable, Equatable { var name: String; var code: String }
        struct Token: Decodable, Equatable, CustomStringConvertible {
            var start: Int
            var len: Int
            var kind: String
            var text: String
            var description: String { "\(kind)[\(start)+\(len)]\(text)" }
        }
        struct Case: Decodable {
            var input: String
            var service: String?
            var scope: String?
            var region: Region?
            var action: String?
            var tokens: [Token]
        }
        var version: Int
        var cases: [Case]
    }

    private static var fixtureURL: URL {
        var u = URL(fileURLWithPath: #filePath)
        for _ in 0..<7 { u.deleteLastPathComponent() }   // → 仓库根
        return u.appendingPathComponent("contract/fixtures/command-parse-v1.json")
    }

    private static let scopeBySceneId = ["ai": "AI", "video": "视频", "other": "其他"]

    /// iOS 解析结果换算成样本的形状（scope 从 tokens 中分开）。
    private struct Normalized: Equatable {
        var service: String?
        var scope: String?
        var region: Fixture.Region?
        var action: String?
        var tokens: [Fixture.Token]
    }

    private static func normalize(_ input: String, _ p: CommandParse) -> Normalized {
        let chars = Array(input)
        func utf16Offset(_ charIndex: Int) -> Int {
            chars[..<charIndex].reduce(0) { $0 + String($1).utf16.count }
        }
        var tokens: [Fixture.Token] = []
        for t in p.tokens where t.kind != .scope {
            guard let r = t.range else { continue }
            let kind: String
            switch t.kind {
            case .service, .scene: kind = "service"
            case .region: kind = "region"
            case .action: kind = "action"
            case .scope: continue
            }
            let start = utf16Offset(r.lowerBound)
            let text = String(chars[r])
            tokens.append(.init(start: start, len: text.utf16.count, kind: kind, text: text))
        }
        let sceneValue = p.tokens.first { $0.kind == .scene }?.value
        return Normalized(
            service: p.serviceName ?? sceneValue,
            scope: p.sceneId.flatMap { scopeBySceneId[$0] },
            region: p.regionName.flatMap { n in p.regionCode.map { .init(name: n, code: $0) } },
            action: p.tokens.first { $0.kind == .action }?.value,
            tokens: tokens
        )
    }

    func testMatchesContractFixtures() throws {
        let data = try Data(contentsOf: Self.fixtureURL)
        let fx = try JSONDecoder().decode(Fixture.self, from: data)
        XCTAssertEqual(fx.version, 1)
        XCTAssertFalse(fx.cases.isEmpty)
        for c in fx.cases {
            let p = CommandTokenizer.parse(c.input)
            let got = Self.normalize(c.input, p)
            let label = "input=\"\(c.input)\""
            XCTAssertEqual(got.service, c.service, "\(label) service")
            XCTAssertEqual(got.scope, c.scope, "\(label) scope")
            XCTAssertEqual(got.region, c.region, "\(label) region")
            XCTAssertEqual(got.action, c.action, "\(label) action")
            XCTAssertEqual(got.tokens, c.tokens, "\(label) tokens")
            // 范围卡片：有服务（或场景关键词带出的范围）时才有 .scope token，且值与样本 scope 一致。
            let scopeTokens = p.tokens.filter { $0.kind == .scope }
            if p.serviceName != nil {
                XCTAssertEqual(scopeTokens.map(\.value), [c.scope].compactMap { $0 }, "\(label) scope token")
                XCTAssertTrue(scopeTokens.allSatisfy { $0.range == nil }, "\(label) scope token 不应有位置")
            } else {
                XCTAssertTrue(scopeTokens.isEmpty, "\(label) 无服务时不应有 scope token")
            }
        }
    }
}
