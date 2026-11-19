// NetworkChangeDetector / Debouncer（契约 §16.a③）。

import XCTest

final class NetworkChangeTests: XCTestCase {
    private let wifiA = NetworkFingerprint(satisfied: true, primaryInterface: "wifi:en0", gateways: ["192.168.1.1"])
    private let wifiB = NetworkFingerprint(satisfied: true, primaryInterface: "wifi:en0", gateways: ["10.0.0.1"])
    private let cell = NetworkFingerprint(satisfied: true, primaryInterface: "cellular:pdp_ip0", gateways: [])
    private let none = NetworkFingerprint(satisfied: false, primaryInterface: nil, gateways: [])

    func testFirstSnapshotIsBaseline() {
        var d = NetworkChangeDetector()
        XCTAssertFalse(d.observe(wifiA))
        XCTAssertEqual(d.last, wifiA)
    }

    func testWifiToCellularAndBack() {
        var d = NetworkChangeDetector()
        _ = d.observe(wifiA)
        XCTAssertTrue(d.observe(cell))
        XCTAssertTrue(d.observe(wifiA))
    }

    func testSameInterfaceDifferentGatewayCountsAsNewNetwork() {
        var d = NetworkChangeDetector()
        _ = d.observe(wifiA)
        XCTAssertTrue(d.observe(wifiB))
    }

    func testIdenticalUpdateIsNotAChange() {
        var d = NetworkChangeDetector()
        _ = d.observe(wifiA)
        XCTAssertFalse(d.observe(wifiA))
        XCTAssertFalse(d.observe(NetworkFingerprint(satisfied: true, primaryInterface: "wifi:en0", gateways: ["192.168.1.1"])))
    }

    func testGatewayOrderIgnored() {
        var d = NetworkChangeDetector()
        _ = d.observe(NetworkFingerprint(satisfied: true, primaryInterface: "wifi:en0", gateways: ["a", "b"]))
        XCTAssertFalse(d.observe(NetworkFingerprint(satisfied: true, primaryInterface: "wifi:en0", gateways: ["b", "a"])))
    }

    /// 同一网络上的短暂掉线再恢复不算变化。
    func testBriefDropOnSameNetworkIsIgnored() {
        var d = NetworkChangeDetector()
        _ = d.observe(wifiA)
        XCTAssertFalse(d.observe(none))
        XCTAssertEqual(d.last, wifiA, "不可用快照不覆盖基线")
        XCTAssertFalse(d.observe(wifiA))
    }

    func testDropThenDifferentNetworkIsAChange() {
        var d = NetworkChangeDetector()
        _ = d.observe(wifiA)
        _ = d.observe(none)
        XCTAssertTrue(d.observe(cell))
    }

    func testReassertingIsIgnored() {
        var d = NetworkChangeDetector()
        _ = d.observe(wifiA)
        XCTAssertFalse(d.observe(cell, reasserting: true))
        XCTAssertEqual(d.last, wifiA, "reasserting 期间不更新基线")
        XCTAssertTrue(d.observe(cell))
    }

    func testReset() {
        var d = NetworkChangeDetector()
        _ = d.observe(wifiA)
        d.reset()
        XCTAssertFalse(d.observe(cell), "重置后重新取基线")
    }

    func testNetworkChangeDelayIsTwoSeconds() {
        XCTAssertEqual(Debouncer.networkChangeDelay, 2)
    }

    func testDebouncerCoalescesBurst() {
        let queue = DispatchQueue(label: "debounce-test")
        let debouncer = Debouncer(delay: 0.2, queue: queue)
        let counter = Counter()
        let done = expectation(description: "fired once")
        for i in 1...5 {
            debouncer.schedule { counter.add(i); if counter.value.count == 1 { done.fulfill() } }
        }
        wait(for: [done], timeout: 2)
        let settle = expectation(description: "settle")
        queue.asyncAfter(deadline: .now() + 0.4) { settle.fulfill() }
        wait(for: [settle], timeout: 2)
        XCTAssertEqual(counter.value, [5], "只执行最后一次")
    }

    func testDebouncerCancel() {
        let queue = DispatchQueue(label: "debounce-cancel")
        let debouncer = Debouncer(delay: 0.1, queue: queue)
        let counter = Counter()
        debouncer.schedule { counter.add(1) }
        debouncer.cancel()
        let settle = expectation(description: "settle")
        queue.asyncAfter(deadline: .now() + 0.3) { settle.fulfill() }
        wait(for: [settle], timeout: 2)
        XCTAssertEqual(counter.value, [])
    }
}

private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [Int] = []
    func add(_ v: Int) { lock.lock(); values.append(v); lock.unlock() }
    var value: [Int] { lock.lock(); defer { lock.unlock() }; return values }
}
