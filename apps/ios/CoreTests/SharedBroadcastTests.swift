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
}
