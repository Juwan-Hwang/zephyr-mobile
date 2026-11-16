// 首页流量（TrafficStore）：回填截断到环形容量、推送按时间戳去重、断开清空。

import XCTest
import ZephyrKit
@testable import ZephyrFeatures

@MainActor
final class TrafficStoreTests: XCTestCase {
    private func sample(_ at: Int64, down: Int64 = 0, up: Int64 = 0) -> TrafficSample {
        TrafficSample(at: at, upBps: up, downBps: down)
    }

    func testStartsEmpty() {
        let s = TrafficStore()
        XCTAssertTrue(s.ring.isEmpty)
        XCTAssertNil(s.latest)
        XCTAssertEqual(s.ring.capacity, TrafficStore.capacity)
    }

    func testSampleMapsDownAndUp() {
        let p = RatePoint(sample(1_000, down: 2_048, up: 512))
        XCTAssertEqual(p, RatePoint(at: 1_000, down: 2_048, up: 512), "up/down 不得互换")
    }

    func testBackfillKeepsNewestWithinCapacity() {
        let s = TrafficStore()
        let n = TrafficStore.capacity + 25
        s.backfill((0..<n).map { sample(Int64($0) * 1_000, down: Int64($0)) })
        XCTAssertEqual(s.ring.count, TrafficStore.capacity)
        XCTAssertEqual(s.ring[0].at, 25_000, "只保留最新的 capacity 个")
        XCTAssertEqual(s.latest?.at, Int64(n - 1) * 1_000)
        XCTAssertEqual(s.latest, s.ring.last)
    }

    func testBackfillReplacesPreviousData() {
        let s = TrafficStore()
        s.backfill([sample(1_000), sample(2_000), sample(3_000)])
        s.backfill([sample(10_000)])
        XCTAssertEqual(s.ring.count, 1)
        XCTAssertEqual(s.latest?.at, 10_000)
    }

    func testEmptyBackfillClearsLatest() {
        let s = TrafficStore()
        s.push(sample(1_000))
        s.backfill([])
        XCTAssertTrue(s.ring.isEmpty)
        XCTAssertNil(s.latest)
    }

    func testPushAppendsAndUpdatesLatest() {
        let s = TrafficStore()
        s.push(sample(1_000, down: 1))
        s.push(sample(2_000, down: 2))
        XCTAssertEqual(s.ring.count, 2)
        XCTAssertEqual(s.latest, RatePoint(at: 2_000, down: 2, up: 0))
    }

    func testPushIgnoresDuplicateAndOlderTimestamps() {
        let s = TrafficStore()
        s.push(sample(2_000, down: 2))
        s.push(sample(2_000, down: 99))   // 重连重复推送同一秒
        s.push(sample(1_000, down: 1))    // 更旧的样本
        XCTAssertEqual(s.ring.count, 1)
        XCTAssertEqual(s.latest?.down, 2, "重复 / 过期样本不得覆盖最新值")
    }

    func testPushAfterBackfillDedupesAgainstBackfilledTail() {
        let s = TrafficStore()
        s.backfill([sample(1_000), sample(2_000)])
        s.push(sample(2_000, down: 7))
        XCTAssertEqual(s.ring.count, 2)
        s.push(sample(3_000, down: 7))
        XCTAssertEqual(s.ring.count, 3)
        XCTAssertEqual(s.latest?.at, 3_000)
    }

    func testClearResetsRingAndLatest() {
        let s = TrafficStore()
        s.push(sample(1_000))
        s.clear()
        XCTAssertTrue(s.ring.isEmpty)
        XCTAssertNil(s.latest)
        s.push(sample(500))
        XCTAssertEqual(s.latest?.at, 500, "清空后不再受旧时间戳去重影响")
    }
}
