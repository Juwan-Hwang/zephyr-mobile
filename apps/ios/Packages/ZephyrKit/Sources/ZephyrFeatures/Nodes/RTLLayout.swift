// 节点页 UIKit 手动布局的 RTL 镜像（产品决策 D-P2-12：ar / fa / ur 需完整 RTL）。
// 各视图仍按 LTR 计算 frame，最后经 `rtl(_:in:)` 水平翻转；尾对齐文字用 `trailingAlignment`。

import UIKit

extension UIView {
    var isRTL: Bool { effectiveUserInterfaceLayoutDirection == .rightToLeft }

    /// 按 LTR 算好的 frame 在 RTL 下沿容器宽度水平翻转。
    func rtl(_ r: CGRect, in width: CGFloat) -> CGRect {
        isRTL ? RTLLayout.mirror(r, in: width) : r
    }

    /// “尾部对齐”：LTR 为右、RTL 为左。
    var trailingAlignment: NSTextAlignment { isRTL ? .left : .right }
}

enum RTLLayout {
    static func mirror(_ r: CGRect, in width: CGFloat) -> CGRect {
        CGRect(x: width - r.maxX, y: r.minY, width: r.width, height: r.height)
    }
}
