// SystemAppIconSwitcher — AppIconSwitching 的系统实现：UIApplication.setAlternateIconName。
// 资源是否存在：读主 Bundle Info.plist 的 CFBundleIcons › CFBundleAlternateIcons（Xcode 由
// ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES 自动生成）。预览 / 快照里没有这些键，自然只显示“深色”。

import UIKit

@MainActor
final class SystemAppIconSwitcher: AppIconSwitching {
    static let shared = SystemAppIconSwitcher()

    var supportsAlternateIcons: Bool { UIApplication.shared.supportsAlternateIcons }

    var alternateIconName: String? { UIApplication.shared.alternateIconName }

    func hasIcon(named name: String) -> Bool {
        let icons = Bundle.main.object(forInfoDictionaryKey: "CFBundleIcons") as? [String: Any]
        let alternates = icons?["CFBundleAlternateIcons"] as? [String: Any]
        return alternates?[name] != nil
    }

    func setAlternateIconName(_ name: String?) async throws {
        try await UIApplication.shared.setAlternateIconName(name)
    }
}
