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
    /// 底部指令栏 52 高、距底 28（`.dock` / `.cmd`）
    static let dockHeight: CGFloat = 52
    static let dockBottom: CGFloat = 12
    /// 细进度条 2（`.bar`）
    static let barThin: CGFloat = 2
    /// 检测中进度条宽 96（原型 scan：`.bar` width 96px）
    static let probeBarWidth: CGFloat = 96
    /// 指令输入框 56 高（`.cin`）
    static let commandFieldHeight: CGFloat = 56
    /// 轨迹节点圆点 11（`.step .dot`，与 ZChainStep regular 一致；流动光点按它定位）
    static let traceDot: CGFloat = 11
    /// 漏斗条 6 高（`.fr .bar2`）
    static let funnelBar: CGFloat = 6
    /// 今日卡片圆角 32（`.tdy .card`）
    static let todayCardRadius: CGFloat = 32
    /// 今日卡片尺寸（原型 346×500）：页面内按宽高比缩放，导出图片按原尺寸 ×3
    static let todayCardSize = CGSize(width: 346, height: 500)
    static let todayCardAspect: CGFloat = todayCardSize.width / todayCardSize.height
    static let todayExportScale: CGFloat = 3
    /// 今日卡片品牌字标高 14（`.cft .wmk`）
    static let todayLockupHeight: CGFloat = 14
    /// 主题选择胶囊高 32（`.pals button`）
    static let paletteChipHeight: CGFloat = 32
    /// 主题色样圆点 20（`.pals i`）
    static let swatch: CGFloat = 20
    /// 1px 细线
    static let hairline: CGFloat = 1

    // MARK: H3（REVIEW-Q1 H 段 P2）补齐的原型尺寸

    /// 首页状态区上边距 18（`.hero` padding-top 18px）
    static let heroTop: CGFloat = 18
    /// 模式与时长之间 14（`.sub` gap 14px）
    static let subGap: CGFloat = 14
    /// 模式 / 时长字号 14（`.sub` font-size 14px）
    static let subFont: CGFloat = 14
    /// 场景行右侧节点名 15（`.ex` font-size 15px）
    static let rowValueFont: CGFloat = 15
    /// 锁图标不透明度 .85（`.pin svg` opacity .85）
    static let pinIconOpacity: Double = 0.85
    /// 场景详情候选行（`.li` padding 13px 14px，font-size 15px）
    static let listItemVertical: CGFloat = 13
    static let listItemHorizontal: CGFloat = 14
    static let listItemFont: CGFloat = 15
    /// 指令 token 卡片（`.pc small` 10.5px / `.pc b` 15px / 圆角 12 / padding 8px 12px）
    static let chipLabelFont: CGFloat = 10.5
    static let chipValueFont: CGFloat = 15
    /// token 卡片依次淡入：每张 +40ms，位移 6（`@keyframes pcIn` translateY(6px)）
    static let chipStagger: Double = 0.04
    static let chipRise: CGFloat = 6
    /// 轨迹页域名 32 light、字距 -0.03em（原型 `#trace .big span` font:300 32px）
    static let traceHostFont: CGFloat = 32
    static let traceHostTracking: CGFloat = -0.03
    /// 服务健康圆点 6（`.svc i` 6×6）
    static let serviceDot: CGFloat = 6
    /// 大字号最多放大 1.6 倍（与 ZDisplay 一致，避免 AX5 下溢出）
    static let displayMaxScale: CGFloat = 1.6
}
