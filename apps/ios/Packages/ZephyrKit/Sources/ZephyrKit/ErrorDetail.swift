// 连接失败的原文（#1 A 真机结论 ③）：契约 §0.5 文案按 code 本地化，message 只给“错误详情”与日志页看。

import Foundation

public extension ZephyrError {
    /// mihomo-mobile 缺地理数据时 zm_start 的错误前缀（契约 §20）。
    static let geodataMissingPrefix = "geodata missing:"
    /// 展开后的错误详情最多显示这么多字符（与 Android FAILURE_DETAIL_MAX_CHARS 一致）。
    static let failureDetailMaxChars = 240

    /// 内核因缺地理数据（geoip.metadb / GeoSite.dat）起不来：首页给专门提示「缺少地理数据」。
    var isGeodataMissing: Bool {
        code == .coreCrashed
            && message.trimmingCharacters(in: .whitespacesAndNewlines)
                .range(of: ZephyrError.geodataMissingPrefix, options: [.caseInsensitive, .anchored]) != nil
    }

    /// 首页失败提示下的“错误详情”：message 折叠空白、截断到 240 字；没有原文为 nil。
    var failureDetail: String? {
        let folded = message.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        guard !folded.isEmpty else { return nil }
        guard folded.count > ZephyrError.failureDetailMaxChars else { return folded }
        return String(folded.prefix(ZephyrError.failureDetailMaxChars - 1)).trimmingCharacters(in: .whitespaces) + "…"
    }
}
