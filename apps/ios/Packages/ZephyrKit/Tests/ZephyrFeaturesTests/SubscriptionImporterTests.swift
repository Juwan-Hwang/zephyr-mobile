// 订阅导入：取消后晚到的结果被丢弃（REVIEW-Q2 P2“订阅导入无取消”）。

import XCTest
import ZephyrKit
import ZephyrMock
@testable import ZephyrFeatures

@MainActor
final class SubscriptionImporterTests: XCTestCase {
    private let link = "https://example.com/sub?token=abc"

    func testCancelDiscardsLateResult() async throws {
        let importer = SubscriptionImporter(engine: MockEngine(seed: 0, clock: .live))
        let pending = Task { await importer.importLink(link) }
        try await waitUntil { importer.isImporting }
        importer.cancel()
        XCTAssertEqual(importer.phase, .idle)
        let result = await pending.value
        XCTAssertNil(result)
        XCTAssertEqual(importer.phase, .idle)
    }

    func testCancelWhenIdleIsNoOp() {
        let importer = SubscriptionImporter(engine: MockEngine(seed: 0, clock: .frozen941))
        importer.cancel()
        XCTAssertEqual(importer.phase, .idle)
    }

    func testImportCompletesWithoutCancel() async {
        let importer = SubscriptionImporter(engine: MockEngine(seed: 0, clock: .frozen941))
        let sub = await importer.importLink(link)
        XCTAssertNotNil(sub)
        if case .done = importer.phase {} else { XCTFail("expected done, got \(importer.phase)") }
    }

    private func waitUntil(_ condition: @MainActor () -> Bool, timeout: TimeInterval = 2) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > deadline { XCTFail("timeout"); return }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
    }
}

extension SubscriptionImporterTests {
    func testCancelledImportIsRolledBack() async throws {
        let engine = MockEngine(seed: 0, clock: .live)
        var before: [Subscription] = []
        for await l in engine.subscriptions() { before = l; break }
        let importer = SubscriptionImporter(engine: engine)
        let pending = Task { await importer.importLink(link) }
        try await waitUntil { importer.isImporting }
        importer.cancel()
        _ = await pending.value
        // 引擎调用在后台完成后撤回；等待其收尾。
        let deadline = Date().addingTimeInterval(3)
        var after: [Subscription] = []
        repeat {
            for await l in engine.subscriptions() { after = l; break }
            if after.map(\.id) == before.map(\.id) { break }
            try await Task.sleep(nanoseconds: 50_000_000)
        } while Date() < deadline
        XCTAssertEqual(after.map(\.id), before.map(\.id))
    }
}
