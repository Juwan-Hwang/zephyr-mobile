// ZephyrGlassHost —— 只给 ZephyrGlassSnapshotTests 当宿主的最小 App（J-4）。
//
// 为什么要它：Liquid Glass（glassEffect）由系统合成，只有挂在 UIWindowScene 上、真正上屏的窗口才画得出来。
// ZephyrSnapshotTests 不挂宿主（xctest 进程没有 scene），layer.render 拍不到玻璃，drawHierarchy 拍出全空图。
// 这个 App 什么都不做，只提供一个 scene；不链接 ZephyrKit，不进 scheme Zephyr，不影响 iOS 18 的 142 张基线。

import SwiftUI

@main
struct ZephyrGlassHostApp: App {
    var body: some Scene {
        WindowGroup { Color.clear }
    }
}
