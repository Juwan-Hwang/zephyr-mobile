// 触感反馈。集中在一处，方便 Reduce Motion / 测试时关闭。
// 优先用 SwiftUI `.sensoryFeedback`（iOS 17）；手势回调里无法挂修饰符的地方用这里。

import SwiftUI
import UIKit

@MainActor
enum HHaptics {
    /// 场景卡左右滑动跨过一个地区（原型 navigator.vibrate(4)）。
    static func tick() {
        let g = UISelectionFeedbackGenerator()
        g.selectionChanged()
    }
    /// 确认切换、应用指令。
    static func confirm() {
        UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.8)
    }
    /// 连接 / 断开。
    static func toggle(on: Bool) {
        UIImpactFeedbackGenerator(style: on ? .medium : .light).impactOccurred()
    }
    static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    static func warning() { UINotificationFeedbackGenerator().notificationOccurred(.warning) }
}
