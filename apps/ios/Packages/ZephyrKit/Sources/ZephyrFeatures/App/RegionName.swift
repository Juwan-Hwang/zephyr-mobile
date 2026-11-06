// 地区码 → 地区名（VoiceOver 朗读、轨迹页"美国 · 7 天未变化"）。
// 与 D 的 ZFlag 一致：跟随系统语言（Locale.current），未知码原样返回。

import Foundation

enum HRegionName {
    static func name(_ code: String) -> String {
        let c = code.uppercased()
        if let n = Locale.current.localizedString(forRegionCode: c), n != c { return n }
        return c
    }
}
