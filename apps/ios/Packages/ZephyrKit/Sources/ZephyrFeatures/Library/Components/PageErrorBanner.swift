// PageErrorBanner — 页面级错误横幅（REVIEW L-P2-11）。外观与首页 RootView 的 ErrorBanner 一致：
// 顶部胶囊（elevated 面、footnote、screenT1），3 秒后消失（带“重试”时 5 秒；VoiceOver 开着时不自动收起带动作的横幅）。
// 出现时警告触感 + VoiceOver 播报；Reduce Motion 下只淡入淡出。
//
// 用法：`.pageErrorBanner($model.error)`；同一页面栈里被盖住的页面传 `isActive: false`，避免两层同时提示。
// 若 App 层想只保留一套实现，可把 RootView.ErrorBanner 换成 `PageErrorBanner(error:onDismiss:)`（同模块 internal）。

import SwiftUI
import UIKit
import ZephyrDesign
import ZephyrKit

struct PageErrorBanner: View {
    let error: PageError
    let onDismiss: () -> Void
    @Environment(\.zAccent) private var accent

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: ZTokens.Space.n4) {
            Text(verbatim: error.message)
                .zType(.footnote)
                .foregroundStyle(ZTokens.Colors.screenT1)
                .fixedSize(horizontal: false, vertical: true)
            if let title = error.retryTitle, let retry = error.retry {
                Button {
                    onDismiss()
                    retry()
                } label: {
                    Text(verbatim: title)
                        .zType(.footnote)
                        .fontWeight(.medium)
                        .foregroundStyle(accent.color)
                        .frame(minHeight: ZTokens.Layout.touchMinIos / 2)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, ZTokens.Space.n5)
        .padding(.vertical, ZTokens.Space.n3)
        .zSurface(.elevated, cornerRadius: ZTokens.Radius.full)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isStaticText)
        .accessibilityAction(named: Text(verbatim: error.retryTitle ?? ZL.tr("关闭"))) {
            onDismiss()
            error.retry?()
        }
    }
}

private struct PageErrorBannerModifier: ViewModifier {
    @Binding var error: PageError?
    var isActive: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.zStaticRendering) private var still

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                ZStack {
                    if isActive, let e = error {
                        PageErrorBanner(error: e) { if error?.id == e.id { error = nil } }
                            .id(e.id)
                            .padding(.horizontal, ZTokens.Space.n4)
                            .padding(.top, ZTokens.Space.n3)
                            .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
                    }
                }
                .animation(still ? nil : ZMotion.gentle(ZMotion.slow, reduceMotion: reduceMotion), value: isActive ? error?.id : nil)
            }
            .task(id: isActive ? error?.id : nil) {
                guard isActive, let e = error else { return }
                HHaptics.warning()
                UIAccessibility.post(notification: .announcement, argument: e.message)
                // 读屏用户需要时间找到“重试”，带动作的横幅不自动收起（下一次错误或点按后替换）。
                if e.retry != nil && UIAccessibility.isVoiceOverRunning { return }
                try? await Task.sleep(nanoseconds: e.displayNanoseconds)
                guard !Task.isCancelled, error?.id == e.id else { return }
                error = nil
            }
    }
}

extension View {
    /// 顶部错误横幅。`isActive = false` 时不显示也不计时（页面被 push 的子页盖住时）。
    func pageErrorBanner(_ error: Binding<PageError?>, isActive: Bool = true) -> some View {
        modifier(PageErrorBannerModifier(error: error, isActive: isActive))
    }
}

#Preview("错误横幅") {
    @Previewable @State var error: PageError? = PageError("无法获取订阅", retry: {})
    Color.clear
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .zPageBackground()
        .pageErrorBanner($error)
        .onTapGesture { error = PageError("网络不可用") }
        .preferredColorScheme(.dark)
}
