// withDeadline：超时必须真正返回（即使 op 不响应取消），正常结果不被超时吞掉。

import XCTest
import ZephyrKit

final class WithDeadlineTests: XCTestCase {
    func testReturnsValueBeforeDeadline() async {
        let v = await withDeadline(2) { () async -> Int? in 42 }
        XCTAssertEqual(v, 42)
    }

    func testTimesOutEvenWhenOpIgnoresCancellation() async {
        let start = Date()
        let v = await withDeadline(0.3) { () async -> Int? in
            // 不可取消的阻塞：用 continuation 悬挂 2 秒后才恢复
            await withCheckedContinuation { (k: CheckedContinuation<Int?, Never>) in
                DispatchQueue.global().asyncAfter(deadline: .now() + 2) { k.resume(returning: 7) }
            }
        }
        XCTAssertNil(v)
        XCTAssertLessThan(Date().timeIntervalSince(start), 1.5, "超时应在 ~0.3 s 返回，而不是等 op 结束")
    }

    func testNilFromOpPassesThrough() async {
        let v = await withDeadline(1) { () async -> Int? in nil }
        XCTAssertNil(v)
    }
}
