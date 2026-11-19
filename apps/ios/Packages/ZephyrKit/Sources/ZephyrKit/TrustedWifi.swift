// TrustedWifi —— 受信任 Wi‑Fi 名称的输入校验（契约 §16.c：SSID 1–32 字节 UTF‑8，去重，≤ 50 项）。
// 设置页“添加”按钮据此禁用并给出原因；系统按需规则（OnDemandPlan）另做去空白去重。

import Foundation

public enum TrustedWifi {
    public static let maxSSIDBytes = 32
    public static let maxCount = 50

    public enum Check: Equatable, Sendable {
        case ok(String)
        case empty
        case duplicate
        case tooLong
        case full
    }

    /// 校验一个待添加的名称（先去掉首尾空白）。
    public static func check(_ raw: String, existing: [String]) -> Check {
        let ssid = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !ssid.isEmpty else { return .empty }
        guard ssid.utf8.count <= maxSSIDBytes else { return .tooLong }
        guard !existing.contains(ssid) else { return .duplicate }
        guard existing.count < maxCount else { return .full }
        return .ok(ssid)
    }
}
