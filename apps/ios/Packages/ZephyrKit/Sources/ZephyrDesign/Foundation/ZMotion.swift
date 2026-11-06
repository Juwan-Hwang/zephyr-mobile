// 动效：时长与曲线全部来自 ZTokens.Time / ZTokens.Easing / ZTokens.Motion。
// Reduce Motion 下：位移/缩放/光晕类动效降级为 nil（瞬时）或短淡入淡出。

import SwiftUI

public enum ZMotion {
    /// 120ms ease-out：按下缩放、徽标 tick。
    public static var micro: Animation { ZTokens.Easing.easeOut(duration: ZTokens.Time.micro) }
    /// 200ms ease-out：颜色、透明度变化。
    public static var standard: Animation { ZTokens.Easing.easeOut(duration: ZTokens.Time.standard) }
    /// 320ms cubic-bezier(0.16,1,0.3,1)：分段滑块、状态字切换、sheet 内容。
    public static var slow: Animation { ZTokens.Easing.spring(duration: ZTokens.Time.slow) }
    /// 页面级 320ms 同曲线。
    public static var page: Animation { ZTokens.Easing.spring(duration: ZTokens.Time.page) }
    /// 物理弹簧（response 0.42 / damping 0.82）：ZConnectButton 旋钮。
    public static var spring: Animation { ZTokens.Motion.spring }

    /// Reduce Motion 时返回 nil（不做位移动画），否则原样返回。
    public static func motion(_ animation: Animation, reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : animation
    }

    /// Reduce Motion 时改为 standard 淡变（仅颜色/透明度），否则原样返回。
    public static func gentle(_ animation: Animation, reduceMotion: Bool) -> Animation {
        reduceMotion ? standard : animation
    }
}
