// 指令 token 化（原型 07 的 parse()）单测。

import XCTest
@testable import ZephyrFeatures

final class CommandTokenizerTests: XCTestCase {

    private func kinds(_ p: CommandParse) -> [CommandToken.Kind] { p.tokens.map(\.kind) }

    func testEmpty() {
        let p = CommandTokenizer.parse("")
        XCTAssertTrue(p.isEmpty)
        XCTAssertNil(p.sceneId)
        XCTAssertNil(p.regionCode)
    }

    func testPrototypeExample() {
        // 原型 07：Gemini 走日本 → 服务 Gemini · 地区 日本 · 范围 AI
        let p = CommandTokenizer.parse("Gemini 走日本")
        XCTAssertEqual(kinds(p), [.service, .region, .scope])
        XCTAssertEqual(p.tokens.map(\.value), ["Gemini", "日本", "AI"])
        XCTAssertEqual(p.serviceName, "Gemini")
        XCTAssertEqual(p.sceneId, "ai")
        XCTAssertEqual(p.regionName, "日本")
        XCTAssertEqual(p.regionCode, "JP")
        // 下划线范围按 Character 下标："Gemini" 0..<6，"日本" 8..<10
        XCTAssertEqual(p.tokens[0].range, 0..<6)
        XCTAssertEqual(p.tokens[1].range, 8..<10)
        XCTAssertNil(p.tokens[2].range)
    }

    func testCaseInsensitiveAndAliases() {
        XCTAssertEqual(CommandTokenizer.parse("CHATGPT tokyo").serviceName, "GPT")
        XCTAssertEqual(CommandTokenizer.parse("CHATGPT tokyo").regionCode, "JP")
        XCTAssertEqual(CommandTokenizer.parse("奈飞 香港").sceneId, "video")
        XCTAssertEqual(CommandTokenizer.parse("奈飞 香港").regionCode, "HK")
        XCTAssertEqual(CommandTokenizer.parse("油管").serviceName, "YouTube")
    }

    func testTwoLetterCodesMustBeStandalone() {
        // "gpt" 里的 "pt"、"youtube" / "plus" 里的 "us" 不能算地区
        XCTAssertNil(CommandTokenizer.parse("gpt").regionCode)
        XCTAssertNil(CommandTokenizer.parse("youtube").regionCode)
        XCTAssertEqual(CommandTokenizer.parse("gpt us").regionCode, "US")
        XCTAssertEqual(CommandTokenizer.parse("claude jp").regionCode, "JP")
        // 先出现嵌在单词里的，后面还有独立的：要找到后面那个
        let p = CommandTokenizer.parse("disney plus us")
        XCTAssertEqual(p.serviceName, "Disney+")
        XCTAssertEqual(p.regionCode, "US")
        XCTAssertEqual(p.tokens.first { $0.kind == .region }?.range, 12..<14)
        // 两字母的服务别名同理："tg" 不能命中 "stg"
        XCTAssertNil(CommandTokenizer.parse("stg").serviceName)
        XCTAssertEqual(CommandTokenizer.parse("tg 新加坡").serviceName, "Telegram")
    }

    func testSceneKeywordWithoutService() {
        let p = CommandTokenizer.parse("视频 走香港")
        XCTAssertEqual(kinds(p), [.scene, .region])
        XCTAssertEqual(p.sceneId, "video")
        XCTAssertNil(p.serviceName)
        XCTAssertEqual(p.regionCode, "HK")
    }

    func testActionAndOrdering() {
        // 输入顺序与展示顺序无关：服务 → 地区 → 操作 → 范围
        let p = CommandTokenizer.parse("直连 github 台湾")
        XCTAssertEqual(kinds(p), [.service, .region, .action, .scope])
        XCTAssertEqual(p.tokens.map(\.value), ["GitHub", "台湾", "直连", "其他"])
        XCTAssertEqual(CommandTokenizer.parse("netflix 4K").tokens.first { $0.kind == .action }?.value, "4K")
    }

    func testOnlyFirstServiceAndRegionCount() {
        let p = CommandTokenizer.parse("claude gemini 日本 美国")
        XCTAssertEqual(p.tokens.filter { $0.kind == .service }.count, 1)
        XCTAssertEqual(p.tokens.filter { $0.kind == .region }.count, 1)
        XCTAssertEqual(p.serviceName, "Claude")
        XCTAssertEqual(p.regionCode, "JP")
    }

    func testPlainDomainHasNoTokens() {
        XCTAssertTrue(CommandTokenizer.parse("example.org").isEmpty)
    }
}
