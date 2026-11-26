// 连接失败的原文（#1 A 真机结论 ③）：契约 §0.5 文案按 code 本地化，message 只给“错误详情”与日志页看。

import Foundation

public extension ZephyrError {
    /// mihomo-mobile 缺地理数据时 zm_start 的错误前缀（契约 §20）。
    static let geodataMissingPrefix = "geodata missing:"

    /// 内核因缺地理数据（geoip.metadb / GeoSite.dat）起不来：首页给专门提示「缺少地理数据」。
    var isGeodataMissing: Bool {
        code == .coreCrashed
            && message.trimmingCharacters(in: .whitespacesAndNewlines)
                .range(of: ZephyrError.geodataMissingPrefix, options: [.caseInsensitive, .anchored]) != nil
    }

    /// 首页失败提示下的“错误详情”（契约 §22.b，U27 修订）：message 先经核心 `redactDiagnostic`
    /// （折叠空白、URL 脱敏、截断 240 字，传 `engine.redactDiagnostic`），平台不再自己折叠 / 截断；脱敏后为空返回 nil。
    func failureDetail(redact: (String) -> String) -> String? {
        let text = redact(message).trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }
}
