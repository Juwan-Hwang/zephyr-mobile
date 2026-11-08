// PageError — 资料库类页面（节点 / 规则 / 订阅 / 设置）的错误提示数据（REVIEW L-P2-11）。
// 与首页一致：错误一律走顶部横幅（PageErrorBanner），成功 / 可撤销的结果才用底部吐司。
// 纯 Swift（无 SwiftUI），可在 Linux 上类型检查与单测。

import Foundation
import ZephyrKit

struct PageError: Identifiable, Equatable {
    let id: UUID
    /// 用户可读文案（ZephyrError.userMessage 或页面给的兜底文案）。
    var message: String
    /// 横幅右侧的动作（“重试”）；nil = 只有文案。
    var retryTitle: String?
    var retry: (@MainActor () -> Void)?

    init(_ message: String, retryTitle: String? = nil, retry: (@MainActor () -> Void)? = nil) {
        self.id = UUID()
        self.message = message
        self.retry = retry
        self.retryTitle = retry == nil ? nil : (retryTitle ?? "重试")
    }

    /// 由引擎错误生成；取消（CancellationError / .cancelled）返回 nil，不打扰用户。
    static func from(_ error: Error, fallback: String, retry: (@MainActor () -> Void)? = nil) -> PageError? {
        if error is CancellationError { return nil }
        if let z = error as? ZephyrError {
            if z.code == .cancelled { return nil }
            return PageError(z.userMessage, retry: retry)
        }
        return PageError(fallback, retry: retry)
    }

    /// 停留时长：带“重试”的多留一会儿，给用户反应时间。
    var displayNanoseconds: UInt64 { retry == nil ? 3_000_000_000 : 5_000_000_000 }

    static func == (lhs: PageError, rhs: PageError) -> Bool { lhs.id == rhs.id }
}
