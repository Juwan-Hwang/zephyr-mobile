// 首页迷你漏斗（规范 §9.3，J-1）：log10 归一、依次缩短、0 也留位置、总宽不超。

import XCTest
import ZephyrKit
@testable import ZephyrFeatures

@MainActor
final class MiniFunnelTests: XCTestCase {
    private func f(_ pool: Int, _ tested: Int, _ ok: Int, _ under: Int) -> NodeFunnel {
        NodeFunnel(sourceCount: 2, poolSize: pool, tested: tested, reachable: ok, underThreshold: under, thresholdMs: 200)
    }

    func testWidthsShrinkLeftToRightAndFit() {
        let w = MiniFunnel.widths(f(10_000_000, 41_288, 3_120, 9), total: 120, gap: 2)
        XCTAssertEqual(w.count, 4)
        for i in 1..<w.count { XCTAssertLessThan(w[i], w[i - 1]) }
        XCTAssertEqual(w.reduce(0, +) + 6, 120, accuracy: 0.001)
        XCTAssertGreaterThan(w[3], 2)   // 9 和 10⁷ 都看得出
    }

    func testZeroCountsKeepMinimum() {
        let w = MiniFunnel.widths(f(512, 0, 0, 0), total: 120, gap: 2)
        XCTAssertEqual(w[1], 2); XCTAssertEqual(w[2], 2); XCTAssertEqual(w[3], 2)
        let empty = MiniFunnel.widths(f(0, 0, 0, 0), total: 120, gap: 2)
        XCTAssertEqual(empty, [2, 2, 2, 2])
    }
}
