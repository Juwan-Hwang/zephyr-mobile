// Mock 漏斗（契约 §15.c）：lede 取原型 2 / 512，各级单调不增。

import XCTest
import ZephyrKit
@testable import ZephyrMock

final class NodeFunnelTests: XCTestCase {
    func testMockFunnelShape() async throws {
        let e = MockEngine(seed: 0, clock: .frozen941)
        let f = try XCTUnwrap(await e.nodeFunnel(maxAgeMs: 24 * 3_600_000, thresholdMs: 300))
        XCTAssertEqual(f.sourceCount, 2)
        XCTAssertEqual(f.poolSize, 512)
        XCTAssertEqual(f.thresholdMs, 300)
        XCTAssertGreaterThan(f.tested, 0)
        XCTAssertLessThanOrEqual(f.tested, f.poolSize)
        XCTAssertLessThanOrEqual(f.reachable, f.tested)
        XCTAssertLessThanOrEqual(f.underThreshold, f.reachable)
    }

    func testNonPositiveThresholdDefaultsTo300() async throws {
        let e = MockEngine(seed: 0, clock: .frozen941)
        let f = try XCTUnwrap(await e.nodeFunnel(maxAgeMs: 0, thresholdMs: 0))
        XCTAssertEqual(f.thresholdMs, 300)
    }

    func testLowerThresholdNeverIncreasesCount() async throws {
        let e = MockEngine(seed: 0, clock: .frozen941)
        let a = try XCTUnwrap(await e.nodeFunnel(maxAgeMs: 0, thresholdMs: 300))
        let b = try XCTUnwrap(await e.nodeFunnel(maxAgeMs: 0, thresholdMs: 50))
        XCTAssertLessThanOrEqual(b.underThreshold, a.underThreshold)
        XCTAssertEqual(a.tested, b.tested)
    }
}
