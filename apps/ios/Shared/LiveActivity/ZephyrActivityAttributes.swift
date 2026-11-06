// 实时活动（锁屏底部卡片 + 灵动岛）的数据模型。App 负责 request / update / end（LiveActivityController），
// ZephyrWidgets 负责渲染（ZephyrLiveActivity）。ContentState 必须远小于 ActivityKit 的 4 KB 上限：场景最多 3 个。

import ActivityKit
import Foundation

struct ZephyrActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable, Sendable {
        var status: SharedState.Status
        var mode: SharedState.Mode
        /// 字节/秒
        var downBps: Int64
        var upBps: Int64
        /// 场景徽标：[JP] AI  [HK] 视频  [TW] 其他
        var scenes: [SharedState.SceneSummary]
        /// 进入 connected 的时间；锁屏卡片右上角计时器从这里开始数（2:14:07）。
        var connectedSince: Date?

        static let maxScenes = 3

        init(status: SharedState.Status, mode: SharedState.Mode, downBps: Int64, upBps: Int64,
             scenes: [SharedState.SceneSummary], connectedSince: Date?) {
            self.status = status; self.mode = mode; self.downBps = downBps; self.upBps = upBps
            self.scenes = Array(scenes.prefix(Self.maxScenes)); self.connectedSince = connectedSince
        }

        init(_ state: SharedState) {
            self.init(status: state.connection.status, mode: state.connection.mode,
                      downBps: state.rate.downBps, upBps: state.rate.upBps,
                      scenes: state.scenes, connectedSince: state.connection.since)
        }
    }

    /// 本次活动开始的时间（不变）。
    var startedAt: Date
    /// 强调色 rawValue（活动期间不变；改设置后下一次活动生效）。
    var accent: String
}

extension ZephyrActivityAttributes.ContentState {
    /// 预览 / 快照：shots/lock.png（2.8 MB/s ↓、194 KB/s ↑、2:14:07）。
    static func prototype(now: Date = Date()) -> Self {
        Self(SharedState.prototype(now: now))
    }
}
