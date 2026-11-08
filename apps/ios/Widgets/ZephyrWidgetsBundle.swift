// ZephyrWidgets 扩展入口：主屏 / 锁屏小组件、实时活动 + 灵动岛、iOS 18 控制中心开关。

import SwiftUI
import WidgetKit
import ZephyrKit

@main
struct ZephyrWidgetsBundle: WidgetBundle {
    init() {
        ZL.bundle = .main   // ZFormat 等返回 String 的文案按系统语言查 Localizable.xcstrings
    }

    var body: some Widget {
        StatusWidget()
        UsageWidget()
        ScenesWidget()
        LockScreenWidget()
        ZephyrLiveActivity()
        if #available(iOS 18.0, *) {
            ZephyrConnectionControl()
        }
    }
}
