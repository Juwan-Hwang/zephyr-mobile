// ZephyrError → 用户可读文案（契约 §0.5：文案由 UI 按 code 本地化，message 只进日志）。
// public：L 的页面也可直接用 `error.userMessage`。

import ZephyrKit

public extension ZephyrError {
    var userMessage: String {
        switch code {
        case .notRunning: "Zephyr 未在运行"
        case .vpnPermissionDenied: "需要允许添加 VPN 配置"
        case .networkUnavailable: "网络不可用"
        case .subscriptionInvalid: "订阅格式无效"
        case .subscriptionFetchFailed: "无法获取订阅"
        case .nodeNotFound: "节点已不存在"
        case .sceneNotFound: "场景已不存在"
        case .groupNotFound: "策略组已不存在"
        case .ruleInputInvalid: "请输入域名或 IP"
        case .coreCrashed: "核心意外退出，已自动重启"
        case .storageFull: "存储空间不足"
        case .cancelled: "已取消"
        case .internal: "出了点问题，请稍后再试"
        }
    }
}
