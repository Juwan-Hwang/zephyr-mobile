// ZephyrError → 用户可读文案（契约 §0.5：文案由 UI 按 code 本地化，message 只进日志）。
// 文案走 String(localized:)（App 的 Localizable.xcstrings，含 en）。public：L 的页面也可直接用 `error.userMessage`。

import ZephyrKit

public extension ZephyrError {
    var userMessage: String {
        switch code {
        case .notRunning: String(localized: "Zephyr 未在运行")
        case .vpnPermissionDenied: String(localized: "需要允许添加 VPN 配置")
        case .networkUnavailable: String(localized: "网络不可用")
        case .subscriptionInvalid: String(localized: "订阅格式无效")
        case .subscriptionFetchFailed: String(localized: "无法获取订阅")
        case .nodeNotFound: String(localized: "节点已不存在")
        case .sceneNotFound: String(localized: "场景已不存在")
        case .groupNotFound: String(localized: "策略组已不存在")
        case .ruleInputInvalid: String(localized: "请输入域名或 IP")
        case .coreCrashed: String(localized: "核心意外退出，已自动重启")
        case .storageFull: String(localized: "存储空间不足")
        case .cancelled: String(localized: "已取消")
        case .internal: String(localized: "出了点问题，请稍后再试")
        }
    }
}
