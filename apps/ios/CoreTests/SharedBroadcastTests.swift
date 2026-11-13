import XCTest

final class SharedBroadcastTests: XCTestCase {
    func testTwoSubscribersShareOneUpstream() async throws {
        let broadcast = SharedBroadcast<Int>()
        let starts = LockedBox(0)
        let upstream: @Sendable () -> AsyncStream<Int> = {
            starts.set(starts.get() + 1)
            return AsyncStream { k in
                let task = Task {
                    var i = 0
                    while !Task.isCancelled { i += 1; k.yield(i); try? await Task.sleep(nanoseconds: 10_000_000) }
                    k.finish()
                }
                k.onTermination = { _ in task.cancel() }
            }
        }
        let a = broadcast.subscribe(upstream: upstream)
        let b = broadcast.subscribe(upstream: upstream)
        XCTAssertEqual(starts.get(), 1)
        XCTAssertEqual(broadcast.subscriberCount, 2)
        var ia = a.makeAsyncIterator(), ib = b.makeAsyncIterator()
        let x = await ia.next(), y = await ib.next()
        XCTAssertNotNil(x)
        XCTAssertNotNil(y)
    }

    func testRestartsAfterAllSubscribersLeave() async throws {
        let broadcast = SharedBroadcast<Int>()
        let starts = LockedBox(0)
        let upstream: @Sendable () -> AsyncStream<Int> = {
            starts.set(starts.get() + 1)
            return AsyncStream { k in
                let task = Task {
                    while !Task.isCancelled { k.yield(1); try? await Task.sleep(nanoseconds: 10_000_000) }
                    k.finish()
                }
                k.onTermination = { _ in task.cancel() }
            }
        }
        do {
            let s = broadcast.subscribe(upstream: upstream)
            var it = s.makeAsyncIterator()
            _ = await it.next()
        }
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(broadcast.subscriberCount, 0)
        let s2 = broadcast.subscribe(upstream: upstream)
        var it2 = s2.makeAsyncIterator()
        let v = await it2.next()
        XCTAssertEqual(v, 1)
        XCTAssertEqual(starts.get(), 2)
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(broadcast.subscriberCount, 1, "旧一代上游收尾不得清掉新订阅者")
    }

    func testReplayLatestGivesLateSubscriberCurrentValue() async throws {
        let broadcast = SharedBroadcast<Int>(replayLatest: true)
        let starts = LockedBox(0)
        let (source, feed) = AsyncStream<Int>.makeStream()
        let upstream: @Sendable () -> AsyncStream<Int> = {
            starts.set(starts.get() + 1)
            return source
        }
        let a = broadcast.subscribe(upstream: upstream)
        var ia = a.makeAsyncIterator()
        feed.yield(42)
        let first = await ia.next()
        XCTAssertEqual(first, 42)
        // 状态流不再变化时，晚到的订阅者也要立即拿到当前值，且不另起上游。
        let b = broadcast.subscribe(upstream: upstream)
        var ib = b.makeAsyncIterator()
        let replayed = await ib.next()
        XCTAssertEqual(replayed, 42)
        XCTAssertEqual(starts.get(), 1)
        feed.finish()
    }

    func testNoReplayByDefault() async throws {
        let broadcast = SharedBroadcast<Int>()
        let (source, feed) = AsyncStream<Int>.makeStream()
        let a = broadcast.subscribe { source }
        var ia = a.makeAsyncIterator()
        feed.yield(1)
        _ = await ia.next()
        let b = broadcast.subscribe { source }
        var ib = b.makeAsyncIterator()
        feed.yield(2)
        let v = await ib.next()
        XCTAssertEqual(v, 2, "流量类流不回放旧值")
        feed.finish()
    }
}
