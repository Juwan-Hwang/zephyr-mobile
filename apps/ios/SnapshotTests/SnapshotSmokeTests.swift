// [A] 占位：project.yml 引用 SnapshotTests 目录但分支里没有，xcodegen 因此失败。
// 真正的页面/小组件快照由 B 补（swift-snapshot-testing，深浅 × AX5 × 强调色）。
import XCTest

final class SnapshotSmokeTests: XCTestCase {
    func testTargetBuilds() {
        XCTAssertNotNil(Bundle(for: SnapshotSmokeTests.self))
    }
}
