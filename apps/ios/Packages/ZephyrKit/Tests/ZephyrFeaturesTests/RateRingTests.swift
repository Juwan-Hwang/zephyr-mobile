// RateRing（首页曲线 300 点环形缓冲）单测。纯逻辑，不依赖 SwiftUI。

import XCTest
@testable import ZephyrFeatures

final class RateRingTests: XCTestCase {

    private func p(_ i: Int64) -> RatePoint { RatePoint(at: i * 1000, down: i * 10, up: i) }

    func testEmpty() {
        let r = RateRing(capacity: 4)
        XCTAssertTrue(r.isEmpty)
        XCTAssertEqual(r.count, 0)
        XCTAssertNil(r.last)
        XCTAssertEqual(r.ordered, [])
        XCTAssertEqual(r.suffix(3), [])
        XCTAssertEqual(r.peakDown(last: 10), 0)
    }

    func testAppendBelowCapacityKeepsOrder() {
        var r = RateRing(capacity: 4)
        r.append(p(1)); r.append(p(2)); r.append(p(3))
        XCTAssertEqual(r.count, 3)
        XCTAssertEqual(r.ordered.map(\.at), [1000, 2000, 3000])
        XCTAssertEqual(r[0], p(1))
        XCTAssertEqual(r.last, p(3))
    }

    func testWrapOverwritesOldest() {
        var r = RateRing(capacity: 3)
        r.append(contentsOf: (1...7).map(p))
        XCTAssertEqual(r.count, 3)
        XCTAssertEqual(r.ordered.map(\.at), [5000, 6000, 7000])
        XCTAssertEqual(r[0], p(5))
        XCTAssertEqual(r[2], p(7))
        XCTAssertEqual(r.last, p(7))
    }

    func testWrapExactlyAtCapacityBoundary() {
        var r = RateRing(capacity: 3)
        r.append(contentsOf: (1...3).map(p))
        XCTAssertEqual(r.ordered.map(\.at), [1000, 2000, 3000])
        r.append(p(4))
        XCTAssertEqual(r.ordered.map(\.at), [2000, 3000, 4000])
    }

    func testSuffix() {
        var r = RateRing(capacity: 5)
        r.append(contentsOf: (1...8).map(p))
        XCTAssertEqual(r.suffix(2).map(\.at), [7000, 8000])
        XCTAssertEqual(r.suffix(99).map(\.at), [4000, 5000, 6000, 7000, 8000])
        XCTAssertEqual(r.suffix(0), [])
    }

    func testPeakDownLooksOnlyAtWindow() {
        var r = RateRing(capacity: 10)
        r.append(RatePoint(at: 1, down: 900, up: 0))
        r.append(RatePoint(at: 2, down: 10, up: 0))
        r.append(RatePoint(at: 3, down: 40, up: 0))
        r.append(RatePoint(at: 4, down: 20, up: 0))
        XCTAssertEqual(r.peakDown(last: 3), 40)
        XCTAssertEqual(r.peakDown(last: 4), 900)
        XCTAssertEqual(r.peakDown(last: 100), 900)
    }

    func testRemoveAllThenReuse() {
        var r = RateRing(capacity: 3)
        r.append(contentsOf: (1...5).map(p))
        r.removeAll()
        XCTAssertTrue(r.isEmpty)
        XCTAssertNil(r.last)
        r.append(p(9))
        XCTAssertEqual(r.ordered, [p(9)])
    }

    func testCapacityOne() {
        var r = RateRing(capacity: 1)
        r.append(p(1)); r.append(p(2))
        XCTAssertEqual(r.count, 1)
        XCTAssertEqual(r.ordered, [p(2)])
    }

    func testEqualityIgnoresPhysicalLayout() {
        // 同样的逻辑内容、不同的写入历史（头指针位置不同）应当相等。
        var a = RateRing(capacity: 3)
        a.append(contentsOf: (1...5).map(p))
        var b = RateRing(capacity: 3)
        b.append(contentsOf: (3...5).map(p))
        XCTAssertEqual(a, b)
        b.append(p(6))
        XCTAssertNotEqual(a, b)
        XCTAssertNotEqual(RateRing(capacity: 2), RateRing(capacity: 3))
    }

    func testDefaultCapacityMatchesHomeChart() {
        var r = RateRing()
        XCTAssertEqual(r.capacity, 300)
        r.append(contentsOf: (0..<1000).map { p(Int64($0)) })
        XCTAssertEqual(r.count, 300)
        XCTAssertEqual(r.ordered.first?.at, 700_000)
        XCTAssertEqual(r.last?.at, 999_000)
    }
}
