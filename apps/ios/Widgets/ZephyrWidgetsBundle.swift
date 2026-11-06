// ZephyrWidgets 扩展入口：主屏 / 锁屏小组件、实时活动 + 灵动岛、iOS 18 控制中心开关。

import SwiftUI
import WidgetKit

@main
struct ZephyrWidgetsBundle: WidgetBundle {
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
