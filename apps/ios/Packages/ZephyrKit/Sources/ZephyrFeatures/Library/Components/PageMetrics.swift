// PageMetrics — 资料库类页面（节点 / 规则 / 订阅 / 设置）共用的版式常量。只由 ZTokens 组合而来，不含魔数。

import CoreGraphics
import ZephyrDesign

enum PageMetrics {
    /// 页面左右边距（原型 .grp margin 16）。
    static let margin = ZTokens.Layout.pageMargin
    /// 页头标题左缩进（原型 .pgh padding 22 = 16 + 6）。
    static let titleInset = ZTokens.Layout.pageMargin + ZTokens.Space.n2
    /// 页面底部留白。
    static let bottomInset = ZTokens.Space.n8
}
