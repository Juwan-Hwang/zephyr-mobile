// SettingsStore — 订阅 settings() 流，并以“全量写回”（契约 §8 updateSettings(patch:)）修改。
// 设置页、订阅页“更新”分组、引导页、资料库子页共用。写入是乐观的：先改本地，失败回滚并给出 lastError（顶部横幅）。

import Observation
import SwiftUI
import ZephyrKit

@MainActor
@Observable
final class SettingsStore {
    @ObservationIgnored let engine: any ZephyrEngine
    /// nil = 还没收到第一帧。
    private(set) var settings: Settings?
    /// 最近一次写回失败（页面以顶部横幅展示，展示后置 nil）。
    var lastError: PageError?
    /// 写回请求的代数：只有最后一次写回失败时才回滚，避免连续拨动开关时被旧请求覆盖。
    @ObservationIgnored private var generation = 0

    init(engine: any ZephyrEngine) { self.engine = engine }

    /// 在 `.task` 里调用；task 取消时结束。
    func start() async {
        for await s in engine.settings() { settings = s }
    }

    /// 修改并全量写回。返回是否成功。
    @discardableResult
    func update(_ mutate: (inout Settings) -> Void) async -> Bool {
        guard let old = settings else { return false }
        var new = old
        mutate(&new)
        guard new != old else { return true }
        settings = new
        generation += 1
        let mine = generation
        do {
            try await engine.updateSettings(patch: new)
            return true
        } catch {
            if mine == generation { settings = old }
            lastError = PageError.from(error, fallback: "无法保存设置")
            return false
        }
    }

    /// 某个字段的双向绑定；settings 未到时读 fallback、写入忽略。
    func binding<T: Equatable & Sendable>(_ keyPath: WritableKeyPath<Settings, T>, fallback: T) -> Binding<T> {
        Binding(
            get: { self.settings?[keyPath: keyPath] ?? fallback },
            set: { value in
                Task { @MainActor in await self.update { $0[keyPath: keyPath] = value } }
            }
        )
    }
}
