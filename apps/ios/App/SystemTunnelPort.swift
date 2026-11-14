// SystemTunnelPort —— CoreEngine 的 TunnelPort 真机实现：NETunnelProviderManager（TunnelController）+ provider message。
//
// 状态：NEVPNStatusDidChange → ConnectionState；模式与错误码取 App Group 的 SharedState（扩展写）。
// 速率：provider message `.traffic`（扩展 1 Hz 采样 mihomo）。模拟器不支持 Packet Tunnel，不会创建本类型。

#if canImport(ZephyrCore)
import Foundation
import NetworkExtension
import ZephyrCore
import ZephyrKit

final class SystemTunnelPort: TunnelPort, @unchecked Sendable {
    private let controller = TunnelController.shared

    var controllerSocketPath: String { AppGroup.controllerSocketPath }
    var configURL: URL { AppGroup.coreDirectory.appendingPathComponent("config.yaml") }

    func states() -> AsyncStream<ConnectionState> {
        AsyncStream(bufferingPolicy: .bufferingNewest(1)) { k in
            // 观察者令牌只用于 removeObserver（线程安全），终止回调里引用它。
            nonisolated(unsafe) let token = NotificationCenter.default.addObserver(forName: .NEVPNStatusDidChange, object: nil, queue: nil) { note in
                guard let conn = note.object as? NEVPNConnection else { return }
                k.yield(Self.state(conn.status, since: conn.connectedDate))
            }
            let task = Task {
                let manager = try? await self.controller.existingManager()
                k.yield(Self.state(manager?.connection.status ?? .disconnected, since: manager?.connection.connectedDate))
            }
            k.onTermination = { _ in
                task.cancel()
                NotificationCenter.default.removeObserver(token)
            }
        }
    }

    /// 直接读系统 VPN 状态，避免 states() 里通知与首值竞争；loadAllFromPreferences 可能不返回，限时 2 s。
    func currentStatus() async -> ConnectionStatus {
        let controller = self.controller
        let raw = await withDeadline(2) { () async -> NEVPNStatus? in
            (try? await controller.existingManager())?.connection.status ?? .disconnected
        }
        return Self.state(raw ?? .disconnected, since: nil).status
    }

    func start() async throws {
        do { try await controller.setConnected(true) } catch {
            throw ZephyrError(code: .vpnPermissionDenied, message: "\(error)")
        }
    }

    func stop() async throws { try await controller.setConnected(false) }

    func applyOnDemand(onDemand: Bool, trustedNetworks: [String], disconnectOnTrusted: Bool, create: Bool) async {
        let plan = OnDemandPlan(onDemand: onDemand, trustedNetworks: trustedNetworks, disconnectOnTrusted: disconnectOnTrusted)
        try? await controller.apply(onDemand: plan, createIfNeeded: create)
    }

    func usageToday() async -> (hourly: [Int64], onlineMillis: Int64)? {
        guard let l = UsageLedger.load()?.today(Date()) else { return nil }
        return (l.hourly, l.onlineMillis)
    }

    func logs(since: Int64, minLevel: String, limit: Int32) async -> String? {
        guard let r = try? await controller.request(.logs(since: since, minLevel: minLevel, limit: limit)), r.result == .ok else { return nil }
        return r.payload
    }

    func urlTest(proxiesJSON: String, url: String, timeoutMs: Int32) async -> String? {
        // 定义可能几十 KB：写进 App Group 文件，消息里只带文件名；用完即删。
        let name = "urltest-\(UUID().uuidString).json"
        let file = AppGroup.coreDirectory.appendingPathComponent(name)
        do {
            try FileManager.default.createDirectory(at: AppGroup.coreDirectory, withIntermediateDirectories: true)
            try Data(proxiesJSON.utf8).write(to: file, options: .atomic)
        } catch { return nil }
        defer { try? FileManager.default.removeItem(at: file) }
        guard let r = try? await controller.request(.urlTest(file: name, url: url, timeoutMs: timeoutMs)), r.result == .ok else { return nil }
        return r.payload
    }

    func setMode(_ mode: ZephyrKit.ProxyMode) async throws {
        try await controller.setMode(SharedState.Mode(rawValue: mode.rawValue) ?? .rule)
    }

    func rate() async -> (up: Int64, down: Int64)? {
        guard let r = try? await controller.request(.traffic), r.status == .connected else { return nil }
        return (r.upBps, r.downBps)
    }

    func reloadConfig() async throws {
        guard let r = try await controller.request(.reloadConfig) else { return }   // 未连接：下次启动读新配置
        if r.result != .ok {
            throw ZephyrError(code: r.errorCode == "subscription_invalid" ? .subscriptionInvalid : .coreCrashed, message: "reload")
        }
    }

    // MARK: 映射

    static func state(_ s: NEVPNStatus, since: Date?) -> ConnectionState {
        let shared = SharedStore.shared.read()
        let mode = ZephyrKit.ProxyMode(rawValue: shared.tunnel.mode.rawValue) ?? .rule
        let status: ConnectionStatus = switch s {
        case .connected: .connected
        case .connecting, .reasserting: .connecting
        case .disconnecting: .disconnecting
        case .invalid, .disconnected: shared.connection.status == .failed ? .failed : .disconnected
        @unknown default: .disconnected
        }
        var error: ZephyrError?
        if status == .failed, let code = shared.connection.errorCode, let c = ErrorCode(rawValue: code) {
            error = ZephyrError(code: c, message: "")
        }
        let millis = since.map { Int64($0.timeIntervalSince1970 * 1000) }
        return ConnectionState(status: status, mode: mode, since: status == .connected ? millis : nil, error: error)
    }
}
#endif
