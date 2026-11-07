// 今日（原型 14，截图 today.png）：生成式流线卡片 + 主题（夜 / 晨 / 雾）+ 分享 / 存储图像。
//
//   ✕
//   [ 卡片 ]
//   (● 夜) (○ 晨) (○ 雾)
//   [ 分享 ]  [ 存储图像 ]
//   图案由今天的流量生成，不含节点名称与 IP 地址。
//
// 导出：ImageRenderer 把 TodayCard 按 346×500 ×3 渲染（流线停在 t = 0，与原型首帧一致）；
//   分享 = ShareLink(Image)；存储 = PhotoKit 仅添加（需要 App 的 NSPhotoLibraryAddUsageDescription，见 NOTES-H.md）。
// 主题记在 @AppStorage("today.theme")。Reduce Motion：流线静止。

import Photos
import SwiftUI
import UIKit
import ZephyrDesign
import ZephyrKit

@MainActor
struct TodayCardView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("today.theme") private var themeRaw = TodayTheme.night.rawValue
    @State private var exported: Image?
    @State private var exportedPNG: Data?
    @State private var saveState: SaveState = .idle

    private enum SaveState: Equatable { case idle, saving, saved, failed }

    private var theme: TodayTheme { TodayTheme(rawValue: themeRaw) ?? .night }
    private var dateText: String { ZFormat.dayTitle(model.now()) }

    var body: some View {
        ZSheet("", doneTitle: nil, accessory: {
            ZIconButton(systemImage: "xmark", label: "关闭") { dismiss() }
        }) {
            VStack(spacing: 0) {
                card
                    .padding(.horizontal, HMetrics.homeInset)
                    .padding(.top, ZTokens.Space.n3)
                TodayThemePicker(selection: Binding(get: { theme }, set: { themeRaw = $0.rawValue }))
                    .padding(.top, ZTokens.Space.n5)
                actions
                    .padding(.horizontal, HMetrics.homeInset)
                    .padding(.top, ZTokens.Space.n6)
                Text(verbatim: footnote)
                    .zType(.caption)
                    .foregroundStyle(saveState == .failed ? ZTokens.Colors.screenRed : ZTokens.Colors.screenT3)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, HMetrics.homeInset)
                    .padding(.top, ZTokens.Space.n4)
                    .padding(.bottom, ZTokens.Space.n8)
            }
        }
        .task { await model.refreshUsage() }
        .task(id: RenderKey(usage: model.usage, theme: theme)) { render() }
    }

    // MARK: 区块

    @ViewBuilder
    private var card: some View {
        if let u = model.usage {
            TodayCard(usage: u, dateText: dateText, theme: theme, animated: !reduceMotion)
                .animation(ZMotion.gentle(ZMotion.page, reduceMotion: reduceMotion), value: theme)
        } else {
            RoundedRectangle(cornerRadius: HMetrics.todayCardRadius, style: .continuous)
                .fill(theme.background)
                .aspectRatio(HMetrics.todayCardAspect, contentMode: .fit)
                .overlay { ProgressView() }
                .accessibilityLabel(Text(verbatim: "正在生成今日卡片"))
        }
    }

    private var actions: some View {
        HStack(spacing: ZTokens.Space.n3) {
            if let exported {
                ShareLink(item: exported, preview: SharePreview(Text(verbatim: "Zephyr · 今日"), image: exported)) {
                    Text(verbatim: "分享")
                        .zType(.body)
                        .foregroundStyle(ZPage.background)
                        .frame(maxWidth: .infinity, minHeight: ZTokens.Layout.touchMinIos)
                        .padding(.vertical, ZTokens.Space.n1)
                        .background(Capsule(style: .continuous).fill(ZTokens.Colors.screenT1))
                        .contentShape(Capsule(style: .continuous))
                }
                .buttonStyle(ZPressStyle(haptic: .none))
            } else {
                ZButton("分享", size: .large, fullWidth: true, isLoading: true) {}
            }
            ZButton(saveTitle, kind: .ghost, size: .large, fullWidth: true, isLoading: saveState == .saving) { save() }
                .disabled(exportedPNG == nil || saveState == .saved)
        }
    }

    private var saveTitle: LocalizedStringKey { saveState == .saved ? "已存储" : "存储图像" }

    private var footnote: String {
        saveState == .failed ? "无法存储。请在“设置”中允许 Zephyr 添加照片。" : "图案由今天的流量生成，不含节点名称与 IP 地址。"
    }

    // MARK: 导出

    private struct RenderKey: Equatable {
        var usage: UsageSummary?
        var theme: TodayTheme
    }

    private func render() {
        guard let u = model.usage else { exported = nil; exportedPNG = nil; return }
        let size = HMetrics.todayCardSize
        let content = TodayCard(usage: u, dateText: dateText, theme: theme, animated: false)
            .frame(width: size.width, height: size.height)
            .environment(\.dynamicTypeSize, .large)
            .zAccent(.blue)
        let r = ImageRenderer(content: content)
        r.scale = HMetrics.todayExportScale
        r.proposedSize = ProposedViewSize(size)
        guard let ui = r.uiImage else { return }
        exported = Image(uiImage: ui)
        exportedPNG = ui.pngData()
        if saveState != .saving { saveState = .idle }
    }

    private func save() {
        guard let data = exportedPNG else { return }
        // 没有 NSPhotoLibraryAddUsageDescription 时访问相册会被系统直接终止进程：先检查，缺失就提示失败。
        guard Bundle.main.object(forInfoDictionaryKey: "NSPhotoLibraryAddUsageDescription") != nil else {
            saveState = .failed
            return
        }
        saveState = .saving
        Task {
            do {
                try await PHPhotoLibrary.shared().performChanges {
                    PHAssetCreationRequest.forAsset().addResource(with: .photo, data: data, options: nil)
                }
                saveState = .saved
                HHaptics.success()
            } catch {
                saveState = .failed
                HHaptics.warning()
            }
        }
    }
}

/// 主题选择（原型 `.pals`）：色样圆点 + 名称的胶囊，选中有底色与描边。
@MainActor
struct TodayThemePicker: View {
    @Binding var selection: TodayTheme
    @ScaledMetric(relativeTo: .footnote) private var swatch = HMetrics.swatch
    @ScaledMetric(relativeTo: .footnote) private var chip = HMetrics.paletteChipHeight

    var body: some View {
        HStack(spacing: ZTokens.Space.n3) {
            ForEach(TodayTheme.allCases) { t in
                let on = t == selection
                Button { selection = t } label: {
                    HStack(spacing: ZTokens.Space.n2) {
                        Circle().fill(t.background)
                            .frame(width: swatch, height: swatch)
                            .overlay { Circle().strokeBorder(ZTokens.Colors.screenT4, lineWidth: HMetrics.hairline) }
                        Text(verbatim: t.title)
                            .zType(.footnote)
                            .foregroundStyle(on ? ZTokens.Colors.screenT1 : ZTokens.Colors.screenT2)
                    }
                    .padding(.leading, ZTokens.Space.n2)
                    .padding(.trailing, ZTokens.Space.n4)
                    .frame(minHeight: chip)
                    .background(Capsule(style: .continuous).fill(on ? AnyShapeStyle(ZCardFill()) : AnyShapeStyle(Color.clear)))
                    .overlay {
                        Capsule(style: .continuous)
                            .strokeBorder(on ? ZTokens.Colors.screenT4 : ZTokens.Colors.screenHl2, lineWidth: HMetrics.hairline)
                    }
                    .frame(minHeight: ZTokens.Layout.touchMinIos)
                    .contentShape(Rectangle())
                }
                .buttonStyle(ZPressStyle(haptic: .selection))
                .accessibilityLabel(Text(verbatim: "\(t.title)色主题"))
                .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
            }
        }
        .frame(maxWidth: .infinity)
        .sensoryFeedback(.selection, trigger: selection)
    }
}

#Preview("今日 · 夜") {
    HPreview(model: .preview()) { TodayCardView() }
}

#Preview("今日 · 浅色 · AX5") {
    HPreview(model: .preview(), scheme: .light) { TodayCardView() }
        .dynamicTypeSize(.accessibility5)
}
