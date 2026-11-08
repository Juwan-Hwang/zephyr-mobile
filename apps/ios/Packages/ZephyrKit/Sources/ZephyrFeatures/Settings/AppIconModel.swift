// AppIconModel — 设置 › 外观 › 应用图标（原型 settings.png：“应用图标 · 深色 ›”，REVIEW L-P2-14）。
//
// 主图标（AppIcon，深色底白色标志）即“深色”；“浅色”是备用图标 AppIcon-Light，需要 App target 提供资源并在
// Info.plist 的 CFBundleIcons › CFBundleAlternateIcons 里登记（ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES）。
// 资源缺失时该选项不出现，行只显示当前值、不可点（见 NOTES-L）。
// 图标不是引擎设置（不进 Settings），状态由系统保存：读 / 写 UIApplication.alternateIconName。
// 纯 Swift（UIKit 部分在 SystemAppIconSwitcher），可在 Linux 上单测。

import Foundation
import Observation

enum AppIconOption: String, CaseIterable, Identifiable, Sendable {
    /// 主图标 AppIcon。
    case dark
    /// 备用图标 AppIcon-Light（资源待补）。
    case light

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dark: "深色"
        case .light: "浅色"
        }
    }

    /// `setAlternateIconName` 的参数；nil = 主图标。
    var alternateName: String? {
        switch self {
        case .dark: nil
        case .light: "AppIcon-Light"
        }
    }

    init(alternateName: String?) {
        self = Self.allCases.first { $0.alternateName == alternateName } ?? .dark
    }
}

/// 系统图标接口（真实实现 SystemAppIconSwitcher；单测注入假实现）。
@MainActor
protocol AppIconSwitching: AnyObject {
    var supportsAlternateIcons: Bool { get }
    var alternateIconName: String? { get }
    /// 备用图标资源是否已打包（主图标恒为 true）。
    func hasIcon(named name: String) -> Bool
    func setAlternateIconName(_ name: String?) async throws
}

@MainActor
@Observable
final class AppIconModel {
    @ObservationIgnored private let switcher: any AppIconSwitching
    private(set) var current: AppIconOption
    private(set) var isChanging = false

    init(switcher: any AppIconSwitching) {
        self.switcher = switcher
        self.current = AppIconOption(alternateName: switcher.alternateIconName)
    }

    /// 可选项：主图标 + 已打包的备用图标。
    var options: [AppIconOption] {
        guard switcher.supportsAlternateIcons else { return [.dark] }
        return AppIconOption.allCases.filter { o in o.alternateName.map(switcher.hasIcon(named:)) ?? true }
    }

    /// 只有一个可选项（资源缺失 / 系统不支持）时行不可点。
    var isSelectable: Bool { options.count > 1 }

    /// 切换图标。成功返回 nil；失败回滚并返回错误（页面以顶部横幅提示）。
    @discardableResult
    func select(_ option: AppIconOption) async -> PageError? {
        guard option != current, !isChanging, options.contains(option) else { return nil }
        let old = current
        current = option
        isChanging = true
        defer { isChanging = false }
        do {
            try await switcher.setAlternateIconName(option.alternateName)
            return nil
        } catch {
            current = old
            return PageError.from(error, fallback: "无法更换应用图标")
        }
    }
}
