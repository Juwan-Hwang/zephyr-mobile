// ZColor —— 随“增强对比度”调整的次级 / 三级文字色（REVIEW-Q2 X-P1-10）。
//
// 基色仍取自 tokens（ZColor.t2 / screenT3）；系统开启“辅助功能 › 显示与文字大小 › 增强对比度”时，
// 把透明度各抬高一档，使次级文字约 ≥ 7:1、三级文字 ≥ 4.5:1。默认对比度下与 tokens 完全一致。
// 正常对比度下浅色三级文字偏淡（约 2.8:1）属 tokens 取值，已在 #1 请 A 上调。

import SwiftUI
import UIKit

public enum ZColor {
    /// 次级文字（tokens screenT2）。
    public static let t2 = boosted(ZTokens.Colors.screenT2, by: 0.22)
    /// 三级文字（tokens screenT3）。
    public static let t3 = boosted(ZTokens.Colors.screenT3, by: 0.30)

    /// 增强对比度下把不透明度加 `delta`（上限 1），其余情况原样返回。
    public static func boosted(_ base: Color, by delta: CGFloat) -> Color {
        Color(UIColor { traits in
            let resolved = UIColor(base).resolvedColor(with: traits)
            guard traits.accessibilityContrast == .high else { return resolved }
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            guard resolved.getRed(&r, green: &g, blue: &b, alpha: &a) else { return resolved }
            return UIColor(red: r, green: g, blue: b, alpha: min(1, a + delta))
        })
    }
}
