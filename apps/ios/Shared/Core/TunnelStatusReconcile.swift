// 隧道状态与错误码的纯值规则（#207 E05 / E07），不碰系统 API，便于单测。
//
// E05：扩展被系统杀掉（jetsam / 崩溃）时来不及写 disconnected，SharedState 会停在 connected。
//      小组件 / 控制中心读状态时用系统 NEVPNStatus 校正（`reconciled(withSystem:since:)`），并把校正结果写回。
// E07：startVPNTunnel / saveToPreferences 的失败只有“权限 / 配置被拒”才是 vpn_permission_denied，
//      其余按契约 §10 归类（`TunnelStartFailure.code(for:)`）。

import Foundation
import NetworkExtension

extension SharedState.Status {
    /// 系统 VPN 状态 → 共享摘要状态。invalid = VPN 配置不存在，视为未连接。
    init(vpn status: NEVPNStatus) {
        switch status {
        case .connected: self = .connected
        case .connecting, .reasserting: self = .connecting
        case .disconnecting: self = .disconnecting
        case .invalid, .disconnected: self = .disconnected
        @unknown default: self = .disconnected
        }
    }
}

extension SharedState {
    /// 以系统状态为准校正连接摘要。`system == nil`（读不到系统状态，如超时）时原样返回。
    /// - 系统未连接、摘要却是 connected / connecting / disconnecting：扩展已不在，改为 disconnected 并清零速率。
    /// - 摘要是 failed 且系统未连接：保留 failed 与错误码（扩展失败时写的，仍然有效）。
    /// - 系统在连接 / 已连接 / 断开中：状态跟随系统；已连接且摘要缺起始时间时用系统的 connectedDate。
    func reconciled(withSystem system: Status?, since systemSince: Date? = nil) -> SharedState {
        guard let system else { return self }
        var s = self
        switch system {
        case .disconnected, .failed:
            guard connection.status != .disconnected, connection.status != .failed else { return self }
            s.connection.status = .disconnected
            s.connection.since = nil
            s.connection.errorCode = nil
            s.connection.errorMessage = nil
        case .connected:
            guard connection.status != .connected || connection.since == nil else { return self }
            s.connection.status = .connected
            s.connection.since = connection.since ?? systemSince
            s.connection.errorCode = nil
            s.connection.errorMessage = nil
        case .connecting, .disconnecting:
            guard connection.status != system else { return self }
            s.connection.status = system
            s.connection.since = nil
            s.connection.errorCode = nil
            s.connection.errorMessage = nil
        }
        if s.connection.status != .connected {
            s.rate.downBps = 0
            s.rate.upBps = 0
        }
        return s
    }
}

/// 启动隧道失败 → 契约 §10 ErrorCode 序列化名。
enum TunnelStartFailure {
    /// NEVPNError 里属于“用户拒绝 / 关掉了 VPN 配置”的码：
    /// - configurationReadWriteFailed：首次 saveToPreferences 时用户在系统弹窗点了“不允许”（permission denied）；
    /// - configurationDisabled：用户在系统设置里关掉了这条 VPN 配置。
    static let permissionCodes: Set<Int> = [NEVPNError.Code.configurationReadWriteFailed.rawValue,
                                            NEVPNError.Code.configurationDisabled.rawValue]

    static func isPermissionDenial(_ error: Error) -> Bool {
        let ns = error as NSError
        return ns.domain == NEVPNErrorDomain && permissionCodes.contains(ns.code)
    }

    /// 系统错误的归类：权限 / 配置被拒 → vpn_permission_denied；其余（配置无效 / 过期 / 连接失败 / 未知 / 非 NE 错误）→ internal。
    /// 扩展自己启动失败（核心崩溃、缺配置、拿不到 utun）不走这里：startVPNTunnel 已返回，扩展把具体码写进 SharedState.connection.errorCode。
    static func code(for error: Error) -> String {
        isPermissionDenial(error) ? "vpn_permission_denied" : "internal"
    }
}
