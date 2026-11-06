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

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UIView {
        let v = UIView()
        v.backgroundColor = .clear
        v.isAccessibilityElement = false          // VoiceOver 走 SwiftUI 的 adjustable action
        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.pan(_:)))
        pan.delegate = context.coordinator
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tap(_:)))
        tap.require(toFail: pan)
        v.addGestureRecognizer(pan)
        v.addGestureRecognizer(tap)
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

        @objc func pan(_ g: UIPanGestureRecognizer) {
            let dx = g.translation(in: g.view).x
            switch g.state {
            case .began: parent.onBegan(); parent.onChanged(dx)
            case .changed: parent.onChanged(dx)
            case .ended, .cancelled, .failed: parent.onEnded(dx)
            default: break
            }
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
