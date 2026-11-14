// 原型里存在、但 ZTokens 尚未提供的尺寸。全部集中在这里（禁止散落魔数），
// 每一项都注明出处（design/prototype/index.html / pages.css）。已在 NOTES-D.md 请求 A 补 token；
// A 补齐后把这里改成转发到 ZTokens 即可，组件代码不用动。

import CoreGraphics

public enum ZMetrics {
    /// 1px 细边框（CSS 1px = 1pt）。
    static let hairline: CGFloat = 1

    // MARK: 字号（pt，均会随 Dynamic Type 缩放）
    /// `.big b` 场景 sheet 76px / 200
    static let displayHero: CGFloat = 76
    /// `.spd b` 首页速率 56px / 200
    static let displayLarge: CGFloat = 56
    /// `.state` / `.pgh .ct b` 44px（状态字 300、页头计数 200）
    static let displayTitle: CGFloat = 44
    /// 追踪页域名：原型 trace.png 实测 ~36pt / 300（CSS 未单列，REVIEW-Q1 H-P2-15）
    static let displayHeadline: CGFloat = 36
    /// `.lc b` 资料库统计 30px / 200
    static let displaySmall: CGFloat = 30
    /// 等宽：`.cc` 地区码 10.5px / 600
    static let monoFlag: CGFloat = 10.5
    /// 等宽：`.gr .tg` 标签 10px
    static let monoTag: CGFloat = 10
    /// 等宽：`.vr .pr` 协议 10.5px
    static let monoMicro: CGFloat = 10.5
    /// 等宽：`.chain em` / `.fs .tm` 12px
    static let monoSmall: CGFloat = 12
    /// 等宽：`.vr .ms` / `.chain b.m` 13px
    static let monoBody: CGFloat = 13
    /// 等宽：`.rt .fs input` 15px
    static let monoLarge: CGFloat = 15
    /// 大数字字距（em）：`.big b` −0.05、`.spd b` −0.045、`.state` −0.035、`.la .sp b` −0.04、`.lc b` −0.03、`.diff .rw b` −0.02
    static let displayTrackingHero: CGFloat = -0.05
    static let displayTrackingLarge: CGFloat = -0.045
    static let displayTrackingTitle: CGFloat = -0.035
    static let displayTrackingMetric: CGFloat = -0.04
    static let displayTrackingSmall: CGFloat = -0.03
    static let displayTrackingCompact: CGFloat = -0.02
    /// `.row .n` 场景名字距 −0.01em
    static let rowTitleTracking: CGFloat = -0.01

    // MARK: 控件
    /// `.sw` 首页连接开关 66×40，旋钮 34，按下加宽到 40
    static let connectWidth: CGFloat = 66
    static let connectHeight: CGFloat = 40
    static let connectKnob: CGFloat = 34
    static let connectKnobPressed: CGFloat = 40
    static let connectInset: CGFloat = 3
    /// `.btn` 40 高；`.ob .foot .btn` 52 高
    static let buttonHeight: CGFloat = 40
    static let buttonHeightLarge: CGFloat = 52
    /// `.btn` padding 0 18
    static let buttonPaddingH: CGFloat = 18
    /// `.ibtn` 36；`.lib` 52
    static let iconButton: CGFloat = 36
    static let iconButtonLarge: CGFloat = 52
    /// `.seg button` 34 高，内边距 3；外圆角 13、滑块圆角 10、滑块阴影 0 2 6 rgba(0,0,0,.4)
    static let segmentHeight: CGFloat = 34
    static let segmentInset: CGFloat = 3
    static let segmentRadius: CGFloat = 13
    static let segmentKnobRadius: CGFloat = 10
    static let segmentShadowOpacity: Double = 0.4
    static let segmentShadowRadius: CGFloat = 3
    static let segmentShadowY: CGFloat = 2
    /// `.fs` 40 高；`.rt .fs` 48 高
    static let fieldHeight: CGFloat = 40
    static let fieldHeightLarge: CGFloat = 48
    /// `.cmd` 52 高胶囊
    public static let dockHeight: CGFloat = 52
    /// `.cc` 地区码徽标 20 高，最小宽 28，圆角 5
    static let flagHeight: CGFloat = 20
    static let flagMinWidth: CGFloat = 28
    static let flagRadius: CGFloat = 5
    /// `.gr .tg` 标签圆角 4
    static let tagRadius: CGFloat = 4
    /// `.grab` 36×5
    static let grabberWidth: CGFloat = 36
    static let grabberHeight: CGFloat = 5
    /// `.toast` 52 高、圆角 18、底部进度 2
    static let toastHeight: CGFloat = 52
    static let toastRadius: CGFloat = 18
    static let toastDrain: CGFloat = 2
    /// `.bar` 2 高；`.meter` 4 高
    static let barThin: CGFloat = 2
    static let barRegular: CGFloat = 4
    /// `.chain .st i` 9；`.step .dot` 11；描边 1.5
    static let chainDot: CGFloat = 9
    static let chainDotLarge: CGFloat = 11
    static let chainDotStroke: CGFloat = 1.5
    /// `.wm i` 状态点 7，外环 4
    static let statusDot: CGFloat = 7
    static let statusRing: CGFloat = 4
    /// `.gr` 行最小高 56
    static let settingsRowMin: CGFloat = 56
    /// `.scanbar` 检测进度条宽 160
    static let scanBarWidth: CGFloat = 160
    /// 首页场景行检测中进度条（原型 scan：`.bar` width 96、高 2、上距 9）
    static let probeBarWidth: CGFloat = 96
    static let probeBarTop: CGFloat = 9
    /// `.row` 场景行：padding 15 16、两栏间距 12；`.row .m` 上距 3；`.pin` 上距 5、图标间距 6；xl 堆叠间距 6
    static let groupRowVertical: CGFloat = 15
    static let groupRowHorizontal: CGFloat = 16
    static let groupRowGap: CGFloat = 12
    static let groupMetaTop: CGFloat = 3
    static let groupPinTop: CGFloat = 5
    static let groupPinGap: CGFloat = 6
    static let groupStackGap: CGFloat = 6
    /// `.pin svg` 锁 9×10，琥珀 .85
    static let pinIconWidth: CGFloat = 9
    static let pinIconOpacity: Double = 0.85
    /// `.row.scrub` 横滑时 5% 强调色底
    static let scrubTint: Double = 0.05
    /// `.cc.tick` 地区码跳动放大
    static let flagTickScale: CGFloat = 1.18
    /// `.track i` 横滑轨道：段高 3、段距 3
    static let scrubHeight: CGFloat = 3
    static let scrubGap: CGFloat = 3
    static let scrubRadius: CGFloat = 2
    /// `.vr` 行左内边距 22（= pageMargin 16 + 6）
    static let rowLeading: CGFloat = ZTokens.Layout.pageMargin + ZTokens.Space.n2
    /// `.vr .ms` 延迟列宽 52
    static let latencyColumn: CGFloat = 52
    /// 节点行在大字体下的高度（原型 xl 66）
    static let rowHeightLarge: CGFloat = 66
    /// 固定行高下节点名字号上限（52 行 17、66 行 19，原型 `.vr .nm` 15 / xl 19）与延迟字号上限（14 / xl 16）
    static let nodeNameCap: CGFloat = 17
    static let nodeNameCapLarge: CGFloat = 19
    static let nodeLatencyCap: CGFloat = 14
    static let nodeLatencyCapLarge: CGFloat = 16
    /// `.vr .nm` padding-left 2
    static let nodeNameLead: CGFloat = 2
    /// 大数字 Dynamic Type 最大放大倍数（避免 AX5 下 76pt 变成 200pt+）
    static let displayMaxScale: CGFloat = 1.6
}
