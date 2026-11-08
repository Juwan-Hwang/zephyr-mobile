// 首页"场景"区（原型 #scenesWrap / #globalWrap）。
//   规则 / 直连模式：场景卡（AI / 视频 / 其他），确认卡插在被切换的场景下方。
//   全局模式：全局模式卡（原型 12）。
//   未连接：卡片整体 55% 透明度（原型 `.off-state .rows .row{opacity:.55}`），仍可浏览与切换。

import SwiftUI
import ZephyrDesign
import ZephyrKit

@MainActor
struct ScenesSection: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // "2 小时前检测"按分钟刷新；只有这一行随时间重算（REVIEW H-P2-7）。
            TimelineView(.everyMinute) { _ in
                ZSectionHeader("场景", trailing: model.connection.mode == .global ? nil : model.scenesTestedText)
            }
            .homeSectionInsets()
            if model.connection.mode == .global {
                GlobalModeCard()
            } else if model.scenes.isEmpty {
                ZCard { Text("添加订阅后，这里会显示 AI、视频等场景。").zType(.footnote).foregroundStyle(ZColor.t3) }
                    .padding(.horizontal, HMetrics.cardInset)
            } else {
                card
            }
        }
        .animation(ZMotion.slow, value: model.connection.mode)
    }

    private var card: some View {
        let firstScrubbable = model.scenes.first(where: Self.isScrubbable)?.id
        return ZCard(padding: 0, cornerRadius: HMetrics.cardRadius) {
            VStack(spacing: 0) {
                ForEach(Array(model.scenes.enumerated()), id: \.element.id) { idx, scene in
                    if idx > 0 { ZDivider() }
                    let pending = model.pendingChange?.sceneId == scene.id ? model.pendingChange : nil
                    let coach = scene.id == firstScrubbable && model.isConnected
                    SceneRow(scene: scene,
                             scrubbable: Self.isScrubbable(scene),
                             showsCoach: coach,
                             isProbing: model.retesting.contains(scene.id),
                             pendingTarget: pending?.to)
                        // 提示气泡画在行下沿之外；抬高层级，盖住下一行之前的分隔线（原型 `.coach` 用 --s1 底，REVIEW H-P2-4）。
                        .zIndex(coach ? 1 : 0)
                    if let pending {
                        SceneChangeConfirm(change: pending, sceneName: scene.name)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
            }
            .animation(ZMotion.slow, value: model.pendingChange)
        }
        .opacity(model.isOn ? 1 : 0.55)
        .padding(.horizontal, HMetrics.cardInset)
    }

    /// 订阅分组场景不参与 Zephyr 优选，不能左右滑动换地区。
    static func isScrubbable(_ s: Scene) -> Bool { s.source != .subscriptionGroup }
}

extension View {
    /// ZSectionHeader 自带左右 n2、上 n6；首页按原型 `.sec` 对齐到 22 / 上 30。
    func homeSectionInsets() -> some View {
        padding(.horizontal, HMetrics.homeInset - ZTokens.Space.n2)
            .padding(.top, HMetrics.sectionTop - ZTokens.Space.n6)
    }
}

#Preview("场景") {
    HPreview(model: .preview()) { ScrollView { ScenesSection() } }
}
