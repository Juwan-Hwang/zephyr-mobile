// zephyr:// 深链解析与反向生成单测。

import XCTest
@testable import ZephyrFeatures

final class DeepLinkTests: XCTestCase {

    private func link(_ s: String) -> DeepLink? { DeepLink(url: URL(string: s)!) }

    func testSimpleHosts() {
        XCTAssertEqual(link("zephyr://home"), .home)
        XCTAssertEqual(link("zephyr://"), .home)
        XCTAssertEqual(link("zephyr://connect"), .connect)
        XCTAssertEqual(link("zephyr://disconnect"), .disconnect)
        XCTAssertEqual(link("zephyr://toggle"), .toggle)
    }

    func testSchemeAndHostAreCaseInsensitive() {
        XCTAssertEqual(link("ZEPHYR://Connect"), .connect)
        XCTAssertEqual(link("Zephyr://MODE/Global"), .mode("global"))
    }

    func testRejectsOtherSchemesAndUnknownHosts() {
        XCTAssertNil(link("https://home"))
        XCTAssertNil(link("zephyr://nope"))
    }

    func testMode() {
        XCTAssertEqual(link("zephyr://mode/rule"), .mode("rule"))
        XCTAssertEqual(link("zephyr://mode/direct"), .mode("direct"))
        XCTAssertNil(link("zephyr://mode/turbo"))
        XCTAssertNil(link("zephyr://mode"))
    }

    func testSheets() {
        XCTAssertEqual(link("zephyr://scene/ai"), .sheet(.scene(id: "ai")))
        XCTAssertNil(link("zephyr://scene"))
        XCTAssertEqual(link("zephyr://connections"), .sheet(.connections(traceID: nil)))
        XCTAssertEqual(link("zephyr://connections/claude.ai"), .sheet(.connections(traceID: "claude.ai")))
        XCTAssertEqual(link("zephyr://today"), .sheet(.today))
        XCTAssertEqual(link("zephyr://library"), .sheet(.library))
    }

    func testCommandAndPushes() {
        XCTAssertEqual(link("zephyr://command"), .command(""))
        XCTAssertEqual(link("zephyr://command?q=Gemini%20%E8%B5%B0%E6%97%A5%E6%9C%AC"), .command("Gemini 走日本"))
        XCTAssertEqual(link("zephyr://nodes"), .push(.nodes(query: "")))
        XCTAssertEqual(link("zephyr://nodes?q=%E6%9D%B1%E4%BA%AC"), .push(.nodes(query: "東京")))
        XCTAssertEqual(link("zephyr://rules"), .push(.rules(query: nil)))
        XCTAssertEqual(link("zephyr://rules?q=github.com"), .push(.rules(query: "github.com")))
        XCTAssertEqual(link("zephyr://subscriptions"), .push(.subscriptions))
        XCTAssertEqual(link("zephyr://settings"), .push(.settings))
    }

    func testRoundTrip() {
        let all: [DeepLink] = [
            .home, .connect, .disconnect, .toggle,
            .mode("rule"), .mode("global"), .mode("direct"),
            .sheet(.scene(id: "video")), .sheet(.connections(traceID: nil)), .sheet(.connections(traceID: "claude.ai")),
            .sheet(.today), .sheet(.library),
            .command(""), .command("Gemini 走日本"), .command("a&b=c?d"),
            .push(.nodes(query: "")), .push(.nodes(query: "东京 IPLC")),
            .push(.rules(query: nil)), .push(.rules(query: "2001:db8::1")),
            .push(.subscriptions), .push(.settings),
        ]
        for l in all {
            XCTAssertEqual(DeepLink(url: l.url), l, "round trip \(l) via \(l.url)")
        }
    }

    func testURLShape() {
        XCTAssertEqual(DeepLink.mode("global").url.absoluteString, "zephyr://mode/global")
        XCTAssertEqual(DeepLink.sheet(.scene(id: "ai")).url.absoluteString, "zephyr://scene/ai")
        XCTAssertEqual(DeepLink.push(.nodes(query: "")).url.absoluteString, "zephyr://nodes")
    }
}
