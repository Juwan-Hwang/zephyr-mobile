// Mock 漏斗（契约 §15.c）：lede 取原型 2 / 512，各级单调不增。

import XCTest
import ZephyrKit
@testable import ZephyrMock

final class NodeFunnelTests: XCTestCase {
    func testMockFunnelShape() async throws {
        let e = MockEngine(seed: 0, clock: .frozen941)
        let f0 = await e.nodeFunnel(maxAgeMs: 24 * 3_600_000, thresholdMs: 300)
        let f = try XCTUnwrap(f0)
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
        let f0 = await e.nodeFunnel(maxAgeMs: 0, thresholdMs: 0)
        let f = try XCTUnwrap(f0)
        XCTAssertEqual(f.thresholdMs, 300)
    }

    func testLowerThresholdNeverIncreasesCount() async throws {
        let e = MockEngine(seed: 0, clock: .frozen941)
        let a0 = await e.nodeFunnel(maxAgeMs: 0, thresholdMs: 300)
        let a = try XCTUnwrap(a0)
        let b0 = await e.nodeFunnel(maxAgeMs: 0, thresholdMs: 50)
        let b = try XCTUnwrap(b0)
        XCTAssertLessThanOrEqual(b.underThreshold, a.underThreshold)
        XCTAssertEqual(a.tested, b.tested)
    }

    // MARK: 契约 §18.a：NodeIndex.reachableCount

    func testNodeIndexReachableComesFromSameFunnel() async throws {
        let e = MockEngine(seed: 0, clock: .frozen941)
        let idx = await e.nodeIndex()
        let f0 = await e.nodeFunnel(maxAgeMs: 24 * 3_600_000, thresholdMs: 200)
        let f = try XCTUnwrap(f0)
        let reachable = try XCTUnwrap(idx.reachableCount)
        let tested = try XCTUnwrap(idx.funnelTested)
        XCTAssertEqual(reachable, Int64(f.reachable))
        XCTAssertEqual(tested, Int64(f.tested))
        XCTAssertGreaterThan(tested, 0)
        XCTAssertLessThanOrEqual(reachable, tested)
    }

    func testThresholdDoesNotChangeReachable() async throws {
        let e = MockEngine(seed: 0, clock: .frozen941)
        let a0 = await e.nodeFunnel(maxAgeMs: 86_400_000, thresholdMs: 100)
        let b0 = await e.nodeFunnel(maxAgeMs: 86_400_000, thresholdMs: 400)
        XCTAssertEqual(try XCTUnwrap(a0).reachable, try XCTUnwrap(b0).reachable)
    }

    /// 过期样本不计入 tested / reachable；maxAge ≤ 0 不过期。
    func testExpiredSamplesAreNotCounted() async throws {
        let e = MockEngine(seed: 0, clock: .frozen941)
        let now = e.clock.now()
        let hour: Int64 = 3_600_000
        // 池里第一个非置顶、有缓存延迟的节点：写一个 2 h 前的实测样本，替换掉它的缓存值。
        var target: NodeId?
        for i in 0..<MockFixtures.funnelPoolSize {
            let r = i % MockNodes.regions.count, j = Int64(i / MockNodes.regions.count)
            let id = MockNodes.id(r, j)
            if MockFixtures.pinnedById[id] == nil, MockNodes.cachedLatency(r, j) != nil { target = id; break }
        }
        let id = try XCTUnwrap(target)
        let before0 = await e.nodeFunnel(maxAgeMs: hour, thresholdMs: 200)
        let before = try XCTUnwrap(before0)
        e.record([LatencyUpdate(id: id, latencyMs: 50, at: now - 2 * hour)])
        let after0 = await e.nodeFunnel(maxAgeMs: hour, thresholdMs: 200)
        let after = try XCTUnwrap(after0)
        XCTAssertEqual(after.tested, before.tested - 1)
        let noExpiry0 = await e.nodeFunnel(maxAgeMs: 0, thresholdMs: 200)
        XCTAssertEqual(try XCTUnwrap(noExpiry0).tested, before.tested)
    }

    // MARK: 契约 v0.7 §19.a：sceneFunnel

    func testSceneFunnelIsScopedAndMonotonic() async throws {
        let e = MockEngine(seed: 0, clock: .frozen941)
        let global0 = await e.nodeFunnel(maxAgeMs: 86_400_000, thresholdMs: 200)
        let global = try XCTUnwrap(global0)
        for id in ["ai", "video", "other"] {
            let f0 = await e.sceneFunnel(sceneId: id, maxAgeMs: 86_400_000, thresholdMs: 200)
            let f = try XCTUnwrap(f0, id)
            XCTAssertEqual(f.sourceCount, global.sourceCount)
            XCTAssertEqual(f.thresholdMs, 200)
            XCTAssertLessThanOrEqual(f.underThreshold, f.reachable, id)
            XCTAssertLessThanOrEqual(f.reachable, f.tested, id)
            XCTAssertLessThanOrEqual(f.tested, f.poolSize, id)
        }
        let ai0 = await e.sceneFunnel(sceneId: "ai", maxAgeMs: 86_400_000, thresholdMs: 200)
        XCTAssertGreaterThan(try XCTUnwrap(ai0).poolSize, 0)
    }

    func testSceneFunnelFollowsNodeFilter() async throws {
        let e = MockEngine(seed: 0, clock: .frozen941)
        let all0 = await e.sceneFunnel(sceneId: "video", maxAgeMs: 0, thresholdMs: 200)
        let all = try XCTUnwrap(all0)
        try? await e.setSceneNodeFilter(sceneId: "video", filter: .uhd)
        let uhd0 = await e.sceneFunnel(sceneId: "video", maxAgeMs: 0, thresholdMs: 200)
        XCTAssertLessThanOrEqual(try XCTUnwrap(uhd0).poolSize, all.poolSize)
    }

    func testSceneFunnelUnknownSceneIsNil() async {
        let e = MockEngine(seed: 0, clock: .frozen941)
        let f = await e.sceneFunnel(sceneId: "nope", maxAgeMs: 0, thresholdMs: 200)
        XCTAssertNil(f)
    }
}
