// 浮层：最近连接（原型 08）、今日卡（原型 14）。
// 这两个视图在 ZephyrFeatures 里是 internal（只由 SheetHost 构造），所以这里用 @testable import。
// Debug 配置下本地 SPM 包以 -enable-testing 编译，scheme 的 test action 用 Debug，可以直接访问。

import SwiftUI
import XCTest
import ZephyrDesign
@testable import ZephyrFeatures
import ZephyrKit

@MainActor
final class ActivitySnapshotTests: XCTestCase {

    private func model(connected: Bool = true) -> AppModel {
        let model = AppModel.preview(connected: connected, frozen: true)
        model.start()
        return model
    }

    func testConnectionsSheet() async {
        await zAssertSnapshots(named: "connections", variants: ZSnapshotVariant.standardPlusAccent(.green, light: true), settle: 0.6) { _ in
            ConnectionsSheet(initialTraceID: nil).environment(model())
        }
    }

    func testConnectionsSheetDisconnected() async {
        await zAssertSnapshots(named: "connections-empty", variants: [.dark], settle: 0.6) { _ in
            ConnectionsSheet(initialTraceID: nil).environment(model(connected: false))
        }
    }

    func testTodayCard() async {
        await zAssertSnapshots(named: "today", variants: ZSnapshotVariant.standardPlusAccent(.orange), settle: 0.6) { _ in
            TodayCardView().environment(model())
        }
    }
}
