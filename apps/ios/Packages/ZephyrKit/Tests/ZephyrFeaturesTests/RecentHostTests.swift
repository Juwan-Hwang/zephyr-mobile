// "刚才"列表的域名聚合单测。

import XCTest
import ZephyrKit
@testable import ZephyrFeatures

final class RecentHostTests: XCTestCase {

    private func c(_ id: String, _ host: String, scene: String? = "ai", node: String = "US-Fixed-01",
                   bytes: Int64 = 100, at: Int64) -> ConnectionInfo {
        ConnectionInfo(id: id, host: host, scene: scene, node: node, upBytes: bytes / 4, downBytes: bytes - bytes / 4, startedAt: at)
    }

    func testGroupsByHostCaseInsensitively() {
        let list = [c("1", "claude.ai", at: 10), c("2", "Claude.AI", bytes: 300, at: 20), c("3", "qq.com", scene: nil, node: "DIRECT", at: 5)]
        let r = RecentHost.aggregate(list)
        XCTAssertEqual(r.map(\.host), ["claude.ai", "qq.com"])
        XCTAssertEqual(r[0].connections, 2)
        XCTAssertEqual(r[0].totalBytes, 400)
        XCTAssertEqual(r[0].lastSeenAt, 20)
        XCTAssertEqual(Set(r[0].connectionIds), ["1", "2"])
        XCTAssertFalse(r[0].isDirect)
        XCTAssertTrue(r[1].isDirect)
    }

    func testSceneAndNodeComeFromLatestConnection() {
        let list = [c("1", "github.com", scene: "other", node: "TW-Fixed-01", at: 50),
                    c("2", "github.com", scene: nil, node: "DIRECT", at: 10)]
        let r = RecentHost.aggregate(list)
        XCTAssertEqual(r[0].scene, "other")
        XCTAssertEqual(r[0].node, "TW-Fixed-01")
    }

    func testOrderingRecencyThenBytesAndLimit() {
        let list = [c("1", "a.com", bytes: 10, at: 5), c("2", "b.com", bytes: 99, at: 5), c("3", "c.com", at: 9)]
        XCTAssertEqual(RecentHost.aggregate(list).map(\.host), ["c.com", "b.com", "a.com"])
        XCTAssertEqual(RecentHost.aggregate(list, limit: 2).map(\.host), ["c.com", "b.com"])
        XCTAssertEqual(RecentHost.aggregate(list, limit: 0), [])
        XCTAssertEqual(RecentHost.aggregate([]), [])
    }
}

@MainActor
final class CloseConnectionsMessageTests: XCTestCase {
    func testMessages() {
        XCTAssertEqual(ActivitySheet.closeMessage(closed: 3, total: 3), "已关闭 3 个连接")
        XCTAssertEqual(ActivitySheet.closeMessage(closed: 0, total: 2), "连接未能关闭")
        XCTAssertEqual(ActivitySheet.closeMessage(closed: 1, total: 3), "2 个连接未能关闭")
    }
}
