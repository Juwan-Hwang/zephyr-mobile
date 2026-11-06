// PendingCommandChannel：投递 → 取出即删除、TTL 过期丢弃、损坏文件、编解码。
// 通道文件在 App Group 容器（无签名测试进程里回退到 Application Support/ZephyrShared），每个用例前后清理。

import XCTest

final class PendingCommandTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_793_929_260)

    override func setUp() {
        super.setUp()
        try? FileManager.default.removeItem(at: PendingCommandChannel.url)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: PendingCommandChannel.url)
        super.tearDown()
    }

    func testTakeWithoutPostReturnsNil() {
        XCTAssertNil(PendingCommandChannel.take(now: t0))
    }

    func testPostThenTakeWithinTTL() throws {
        try PendingCommandChannel.post(.setConnected(true), now: t0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: PendingCommandChannel.url.path))
        XCTAssertEqual(PendingCommandChannel.take(now: t0.addingTimeInterval(5)), .setConnected(true))
    }

    func testTakeConsumesCommand() throws {
        try PendingCommandChannel.post(.setMode(.global), now: t0)
        XCTAssertEqual(PendingCommandChannel.take(now: t0), .setMode(.global))
        XCTAssertNil(PendingCommandChannel.take(now: t0), "取出后应删除，不能重复执行")
        XCTAssertFalse(FileManager.default.fileExists(atPath: PendingCommandChannel.url.path))
    }

    func testTTLBoundaryIsInclusive() throws {
        try PendingCommandChannel.post(.setConnected(false), now: t0)
        XCTAssertEqual(PendingCommandChannel.take(now: t0.addingTimeInterval(PendingCommandChannel.ttl)), .setConnected(false))
    }

    func testExpiredCommandIsDroppedAndDeleted() throws {
        try PendingCommandChannel.post(.setConnected(true), now: t0)
        XCTAssertNil(PendingCommandChannel.take(now: t0.addingTimeInterval(PendingCommandChannel.ttl + 1)))
        XCTAssertFalse(FileManager.default.fileExists(atPath: PendingCommandChannel.url.path),
                       "过期命令也要删除，否则下次冷启动还会读到")
    }

    func testLatestPostWins() throws {
        try PendingCommandChannel.post(.setMode(.rule), now: t0)
        try PendingCommandChannel.post(.setMode(.direct), now: t0.addingTimeInterval(1))
        XCTAssertEqual(PendingCommandChannel.take(now: t0.addingTimeInterval(2)), .setMode(.direct))
    }

    func testCorruptFileIsDroppedAndDeleted() throws {
        try Data("{\"command\":42}".utf8).write(to: PendingCommandChannel.url)
        XCTAssertNil(PendingCommandChannel.take(now: t0))
        XCTAssertFalse(FileManager.default.fileExists(atPath: PendingCommandChannel.url.path))
    }

    func testTTLIsShort() {
        XCTAssertLessThanOrEqual(PendingCommandChannel.ttl, 60, "过期命令不应在下次冷启动时突然生效")
    }

    func testCommandCodableRoundTrip() throws {
        let all: [PendingCommand] = [.setConnected(true), .setConnected(false)] + SharedState.Mode.allCases.map { .setMode($0) }
        for command in all {
            let data = try SharedStore.encoder.encode(command)
            XCTAssertEqual(try SharedStore.decoder.decode(PendingCommand.self, from: data), command)
        }
    }
}
