// 只识别水平方向的拖动 + 轻点（场景卡左右滑动切换地区）。
//
// 为什么不用 SwiftUI DragGesture：在 iOS 17 的纵向 ScrollView 里，子视图的 DragGesture 会抢走纵向滚动。
// 这里用 UIPanGestureRecognizer，在 gestureRecognizerShouldBegin 里只放行 |vx| > |vy| 的拖动，
// 纵向手势立即失败、交还给 ScrollView。iOS 18 可换成 UIGestureRecognizerRepresentable。

import SwiftUI
import UIKit

@MainActor
struct HorizontalPanOverlay: UIViewRepresentable {
    var onTap: @MainActor () -> Void
    var onBegan: @MainActor () -> Void
    var onChanged: @MainActor (CGFloat) -> Void
    var onEnded: @MainActor (CGFloat) -> Void
    /// 按下态（原型 `.row:active`）：手指落下即高亮，移动超过 10pt、开始横滑或抬起时取消（REVIEW H-P1-3）。
    var onPressChanged: @MainActor (Bool) -> Void = { _ in }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UIView {
        let v = UIView()
        v.backgroundColor = .clear
        v.isAccessibilityElement = false          // VoiceOver 走 SwiftUI 的 adjustable action
        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.pan(_:)))
        pan.delegate = context.coordinator
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tap(_:)))
        tap.require(toFail: pan)
        let press = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.press(_:)))
        press.minimumPressDuration = 0.06
        press.allowableMovement = 10
        press.cancelsTouchesInView = false
        press.delegate = context.coordinator
        v.addGestureRecognizer(pan)
        v.addGestureRecognizer(tap)
        v.addGestureRecognizer(press)
        return v
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.parent = self
    }

    @MainActor
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var parent: HorizontalPanOverlay
        init(_ parent: HorizontalPanOverlay) { self.parent = parent }

        @objc func tap(_ g: UITapGestureRecognizer) {
            if g.state == .ended { parent.onTap() }
        }

        @objc func press(_ g: UILongPressGestureRecognizer) {
            switch g.state {
            case .began: parent.onPressChanged(true)
            case .ended, .cancelled, .failed: parent.onPressChanged(false)
            default: break
            }
        }

        @objc func pan(_ g: UIPanGestureRecognizer) {
            let dx = g.translation(in: g.view).x
            switch g.state {
            case .began: parent.onPressChanged(false); parent.onBegan(); parent.onChanged(dx)
            case .changed: parent.onChanged(dx)
            case .ended, .cancelled, .failed: parent.onEnded(dx)
            default: break
            }
        }

        /// 按下态识别器与点按、横滑、外层 ScrollView 同时识别，不抢任何手势。
        nonisolated func gestureRecognizer(_ g: UIGestureRecognizer,
                                           shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            g is UILongPressGestureRecognizer || other is UILongPressGestureRecognizer
        }

        nonisolated func gestureRecognizerShouldBegin(_ g: UIGestureRecognizer) -> Bool {
            MainActor.assumeIsolated {
                guard let pan = g as? UIPanGestureRecognizer else { return true }
                let v = pan.velocity(in: pan.view)
                return abs(v.x) > abs(v.y) * 1.2
            }
        }
    }
}
