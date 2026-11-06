// H 负责页面里用到、但 ZTokens 尚无对应 token 的原型尺寸。全部集中在此（禁止散落魔数），注明出处。
// A/D 补齐 token 后改为转发即可。（ZephyrDesign 的 ZMetrics 是 internal，Features 用不到。）

import CoreGraphics

enum HMetrics {
    /// 首页左右留白 22（`.hero` / `.sec` padding 22px）
    static let homeInset: CGFloat = 22
    /// 卡片外边距 12（`.rows` margin 0 12px）
    static let cardInset: CGFloat = 12
    /// 首页卡片圆角 22（`.rows` border-radius 22px）
    static let cardRadius: CGFloat = 22
    /// 曲线区高度 150（`.wind` height 150px）
    static let chartHeight: CGFloat = 150
    /// 区块标题上方留白 30（`.sec` padding-top 30px）
    static let sectionTop: CGFloat = 30
    /// 场景行内边距（`.row` padding 15px 16px）
    static let rowVertical: CGFloat = 15
    static let rowHorizontal: CGFloat = 16
    /// 左右滑动切换地区：每 42pt 跨一个地区（原型 Math.round(dx/42)）
    static let scrubStep: CGFloat = 42
    /// 地区码徽标 20 高、最小宽 28、圆角 5（`.cc`）
    static let flagHeight: CGFloat = 20
    static let flagMinWidth: CGFloat = 28
    static let flagRadius: CGFloat = 5
    /// 连接开关 66×40，旋钮 34，内边距 3（`.sw`）
    static let switchWidth: CGFloat = 66
    static let switchHeight: CGFloat = 40
    static let switchKnob: CGFloat = 34
    static let switchKnobPressed: CGFloat = 40
    static let switchInset: CGFloat = 3
    /// 底部指令栏 52 高、距底 28（`.dock` / `.cmd`）
    static let dockHeight: CGFloat = 52
    static let dockBottom: CGFloat = 12
    /// 吐司 52 高、圆角 18、进度条 2（`.toast`）
    static let toastHeight: CGFloat = 52
    static let toastRadius: CGFloat = 18
    static let toastDrain: CGFloat = 2
    /// 细进度条 2（`.bar`）
    static let barThin: CGFloat = 2
    /// 检测中进度条宽 96（原型 scan：`.bar` width 96px）
    static let probeBarWidth: CGFloat = 96
    /// 指令输入框 56 高（`.cin`）
    static let commandFieldHeight: CGFloat = 56
    /// 轨迹节点圆点 11、描边 1.5（`.step .dot`）
    static let traceDot: CGFloat = 11
    static let traceDotStroke: CGFloat = 1.5
    /// 漏斗条 6 高（`.fr .bar2`）
    static let funnelBar: CGFloat = 6
    /// 今日卡片圆角 32（`.tdy .card`）
    static let todayCardRadius: CGFloat = 32
    /// 今日卡片宽高比（原型 346×500）
    static let todayCardAspect: CGFloat = 346.0 / 500.0
    /// 主题色样圆点 20（`.pals i`）
    static let swatch: CGFloat = 20
    /// 1px 细线
    static let hairline: CGFloat = 1
}
