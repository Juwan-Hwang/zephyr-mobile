// 可撤销提示（原型 `.toast`：52 高、圆角 18，"已切换至东京 03 · 撤销"，底部 2pt 进度条在停留时间内耗尽）。
// 停留 ZTokens.Motion.undoWindow 秒后自动消失。待替换为 D 的 ZToast。
// VoiceOver：出现时朗读文案；"撤销"是独立按钮。Reduce Motion：无位移、无进度动画。

import SwiftUI
import UIKit
import ZephyrDesign

struct UndoToastHost: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            if let t = model.toast {
                UndoToastView(toast: t)
                    .id(t.id)
                    .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                    .task(id: t.id) {
                        try? await Task.sleep(nanoseconds: UInt64(ZTokens.Motion.undoWindow * 1_000_000_000))
                        model.dismissToast(t.id)
                    }
            }
        }
        .animation(ZMotion.slow, value: model.toast)
    }
}

private struct UndoToastView: View {
    let toast: UndoToast
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drained = false
    @ScaledMetric(relativeTo: .body) private var height = HMetrics.toastHeight

    var body: some View {
        HStack(spacing: ZTokens.Space.n3) {
            Text(verbatim: toast.message)
                .zType(.footnote)
                .foregroundStyle(ZTokens.Colors.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
            if toast.undo != nil {
                Button {
                    Task { await model.performUndo() }
                } label: {
                    Text(verbatim: "撤销")
                        .zType(.footnote).fontWeight(.medium)
                        .foregroundStyle(ZAccentStyle())
                        .padding(.horizontal, ZTokens.Space.n4)
                        .frame(minHeight: ZTokens.Layout.touchMinIos)
                        .contentShape(Rectangle())
                }
                .buttonStyle(ZPressStyle(haptic: .medium))
            }
        }
        .padding(.leading, ZTokens.Space.n5)
        .padding(.trailing, ZTokens.Space.n2)
        .frame(minHeight: height)
        .background(ZKnobFill())
        .overlay(alignment: .bottomLeading) {
            if toast.undo != nil && !reduceMotion {
                GeometryReader { geo in
                    Rectangle().fill(ZAccentStyle())
                        .frame(width: drained ? 0 : geo.size.width, height: HMetrics.toastDrain)
                        .frame(maxHeight: .infinity, alignment: .bottom)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: HMetrics.toastRadius, style: .continuous))
        .zSurface(.elevated, cornerRadius: HMetrics.toastRadius)
        .padding(.horizontal, HMetrics.cardInset)
        .onAppear {
            withAnimation(.linear(duration: ZTokens.Motion.undoWindow)) { drained = true }
            UIAccessibility.post(notification: .announcement, argument: toast.message)
            HHaptics.success()
        }
        .accessibilityElement(children: .contain)
    }
}

#Preview {
    let model = AppModel.preview()
    model.toast = UndoToast(message: "已切换至东京 03") {}
    return HPreview(model: model) { VStack { Spacer(); UndoToastHost() } }
}
