// TunnelController —— 系统 VPN 配置（NETunnelProviderManager）的唯一入口。
//
// - 首次连接时创建 “Zephyr” VPN 配置（系统会弹 VPN 授权；拒绝 → ErrorCode.vpn_permission_denied）。
// - 启动：startVPNTunnel（按设置恢复按需）；停止：先暂停按需再 stopVPNTunnel（#207 E02）；
//   模式：写 SharedState.tunnel.mode 并 sendProviderMessage(.setMode)。
// - 只有权限 / 配置被拒才报 permissionDenied，其余系统错误原样抛出，由调用方按 `errorCode(for:)` 归类（#207 E07）。
// - 小组件 / 控制中心读状态走 `reconciledSharedState()`：以系统 NEVPNStatus 校正 SharedState（#207 E05）。
// - 模拟器不支持 Packet Tunnel：改走 PendingCommand（交给正在运行的 App 内 MockEngine）。
// App 侧的 CoreEngine（ZephyrCore，Release）也应通过它启动隧道后再调用引擎的 connect()（契约 §11）。

import Foundation
import NetworkExtension

final class TunnelController: ConnectionControlling, @unchecked Sendable {
    static let shared = TunnelController()

    /// 与 project.yml 中 PacketTunnel 的 PRODUCT_BUNDLE_IDENTIFIER 一致。
    static let providerBundleIdentifier = "app.zephyr.mobile.PacketTunnel"
    static let localizedDescription = "Zephyr"
    /// App 写、扩展读的 mihomo 配置（与 TunnelConfiguration.defaultConfigURL 一致）。
    static var defaultConfigURL: URL { AppGroup.coreDirectory.appendingPathComponent("config.yaml") }

    enum TunnelError: Error, LocalizedError, Sendable {
        case permissionDenied
        case notConnected
        case badResponse
        /// 还没有 mihomo 配置（App 里没添加过订阅）：扩展进程无法生成配置，需要先打开 App。
        case configMissing

        var errorDescription: String? {
            switch self {
            case .permissionDenied: String(localized: "没有 VPN 权限，请在 Zephyr 里允许添加 VPN 配置。")
            case .notConnected: String(localized: "Zephyr 未连接。")
            case .badResponse: String(localized: "代理扩展没有响应。")
            case .configMissing: String(localized: "还没有可用的配置，请先打开 Zephyr 添加订阅。")
            }
        }

        /// 契约 §10 ErrorCode 序列化名（configMissing 与扩展找不到配置时一致，见 §14.x）。
        var code: String {
            switch self {
            case .permissionDenied: "vpn_permission_denied"
            case .configMissing: "subscription_invalid"
            case .notConnected: "not_running"
            case .badResponse: "internal"
            }
        }
    }

    /// `setConnected` 抛出的任意错误 → 契约 §10 ErrorCode 序列化名。
    static func errorCode(for error: Error) -> String {
        if let e = error as? TunnelError { return e.code }
        return TunnelStartFailure.code(for: error)
    }

    // MARK: ConnectionControlling

    func setConnected(_ on: Bool) async throws {
        #if targetEnvironment(simulator)
        try PendingCommandChannel.post(.setConnected(on))
        #else
        if on {
            // 配置由 App 的 CoreEngine 在订阅 / 设置变更时写好；没有就明确提示，而不是启动后立刻失败。
            guard let size = try? TunnelController.defaultConfigURL.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > 0 else {
                throw TunnelError.configMissing
            }
        }
        if on {
            let manager = try await loadOrCreateManager()
            // 手动断开时暂停过按需：按设置恢复（规则由 apply(onDemand:) 按当前设置写好）。
            let resume = OnDemandPause.enabledBeforeStart(hasRules: !(manager.onDemandRules ?? []).isEmpty,
                                                          current: manager.isOnDemandEnabled)
            if !manager.isEnabled || resume != nil {
                manager.isEnabled = true
                if let resume { manager.isOnDemandEnabled = resume }
                do { try await manager.saveToPreferences() } catch { throw Self.permissionMapped(error) }
                try await manager.loadFromPreferences()
            }
            try await start(manager)
        } else {
            guard let manager = try await existingManager() else { return }
            // 开着按需时直接 stop，规则末尾的 NEOnDemandRuleConnect 会让系统马上重连（#207 E02）。先关按需并保存。
            if let off = OnDemandPause.enabledBeforeStop(current: manager.isOnDemandEnabled) {
                manager.isOnDemandEnabled = off
                do {
                    try await manager.saveToPreferences()
                    try await manager.loadFromPreferences()
                } catch {
                    // 保存失败也要断开；系统可能按规则重连，但不能让用户点了断开却什么都不发生。
                }
            }
            manager.connection.stopVPNTunnel()
        }
        #endif
    }

    /// startVPNTunnel：配置过期 / 无效（另一进程刚改过配置）时重新 load 再试一次；
    /// 权限 / 配置被拒 → permissionDenied；其余系统错误原样抛出（#207 E07）。
    private func start(_ manager: NETunnelProviderManager) async throws {
        do {
            try manager.connection.startVPNTunnel(options: nil)
        } catch let error as NSError where error.domain == NEVPNErrorDomain
            && (error.code == NEVPNError.Code.configurationStale.rawValue || error.code == NEVPNError.Code.configurationInvalid.rawValue) {
            try await manager.loadFromPreferences()
            do { try manager.connection.startVPNTunnel(options: nil) } catch { throw Self.permissionMapped(error) }
        } catch {
            throw Self.permissionMapped(error)
        }
    }

    /// 权限 / 配置被拒 → permissionDenied；其余错误原样返回。
    private static func permissionMapped(_ error: Error) -> Error {
        TunnelStartFailure.isPermissionDenial(error) ? TunnelError.permissionDenied : error
    }

    func setMode(_ mode: SharedState.Mode) async throws {
        try SharedStore.shared.update { $0.tunnel.mode = mode; $0.connection.mode = mode }
        #if targetEnvironment(simulator)
        try PendingCommandChannel.post(.setMode(mode))
        #else
        if let session = try await activeSession() {
            _ = try await send(.setMode(mode), via: session)
        }
        #endif
    }

    // MARK: 查询

    /// 向扩展发请求；未连接返回 nil。
    func request(_ request: TunnelRequest) async throws -> TunnelResponse? {
        guard let session = try await activeSession() else { return nil }
        return try await send(request, via: session)
    }

    /// 把按需规则写进系统 VPN 配置。配置不存在且 `createIfNeeded == false` 时什么都不做。
    func apply(onDemand plan: OnDemandPlan, createIfNeeded: Bool) async throws {
        let manager: NETunnelProviderManager
        if createIfNeeded { manager = try await loadOrCreateManager() } else if let found = try await existingManager() { manager = found } else { return }

        var rules: [NEOnDemandRule] = []
        if !plan.disconnectSSIDs.isEmpty {
            let disconnect = NEOnDemandRuleDisconnect()
            disconnect.interfaceTypeMatch = .wiFi
            disconnect.ssidMatch = plan.disconnectSSIDs
            rules.append(disconnect)
        }
        if plan.connectElsewhere { rules.append(NEOnDemandRuleConnect()) } else if !rules.isEmpty { rules.append(NEOnDemandRuleIgnore()) }

        // 用户手动断开后按需处于暂停：设置变化只更新规则，不重新启用（下次手动连接时恢复，#207 E02）。
        let paused = OnDemandPause.isPaused(hasRules: !(manager.onDemandRules ?? []).isEmpty, enabled: manager.isOnDemandEnabled)
        let enabled = OnDemandPause.enabledAfterApply(plan: plan, wasPaused: paused)
        // 没有变化就不写系统配置（每次保存都会触发 NEVPNConfigurationChange 通知）。
        let sameRules = (manager.onDemandRules ?? []).count == rules.count
            && zip(manager.onDemandRules ?? [], rules).allSatisfy { type(of: $0) == type(of: $1) && ($0 as? NEOnDemandRuleDisconnect)?.ssidMatch == ($1 as? NEOnDemandRuleDisconnect)?.ssidMatch }
        if manager.isOnDemandEnabled == enabled && sameRules { return }
        manager.onDemandRules = rules.isEmpty ? nil : rules
        manager.isOnDemandEnabled = enabled
        try await manager.saveToPreferences()
        try await manager.loadFromPreferences()
    }

    // MARK: 状态校正（#207 E05）

    /// 系统 VPN 状态与连接起始时间；没有 VPN 配置为 (.invalid, nil)；读取超过 `timeout` 秒为 nil。
    func systemStatus(timeout: TimeInterval = 2) async -> (status: NEVPNStatus, since: Date?)? {
        await Self.withTimeout(timeout) { [self] in
            guard let manager = try? await existingManager() else { return (NEVPNStatus.invalid, nil) }
            return (manager.connection.status, manager.connection.connectedDate)
        }
    }

    /// 以系统状态为准的共享摘要：扩展被杀后 SharedState 可能停在 connected，读到不一致就校正并写回，
    /// 让小组件、控制中心、实时活动不再显示假“已连接”。读不到系统状态时原样返回 SharedState。
    func reconciledSharedState(store: SharedStore = .shared) async -> SharedState {
        let current = store.read()
        #if targetEnvironment(simulator)
        return current   // 模拟器没有 Packet Tunnel：状态由 App 内 MockEngine 写入，不能被“系统未连接”覆盖
        #else
        guard let sys = await systemStatus() else { return current }
        let system = SharedState.Status(vpn: sys.status)
        let fixed = current.reconciled(withSystem: system, since: sys.since)
        guard fixed.connection != current.connection else { return current }
        // 写回时对最新内容再算一次，避免覆盖扩展刚写入的状态。
        let written = try? store.update { state in state = state.reconciled(withSystem: system, since: sys.since) }
        DarwinNotifier.post(.tunnelStatus)
        return written ?? fixed
        #endif
    }

    private static func withTimeout<T: Sendable>(_ seconds: TimeInterval, _ op: @escaping @Sendable () async -> T) async -> T? {
        await withCheckedContinuation { (cont: CheckedContinuation<T?, Never>) in
            let once = ResumeOnce(cont)
            Task { once.resume(await op()) }
            Task {
                try? await Task.sleep(nanoseconds: UInt64(max(0, seconds) * 1_000_000_000))
                once.resume(nil)
            }
        }
    }

    // MARK: 内部

    func loadOrCreateManager() async throws -> NETunnelProviderManager {
        let managers = try await NETunnelProviderManager.loadAllFromPreferences()
        if let existing = managers.first(where: {
            ($0.protocolConfiguration as? NETunnelProviderProtocol)?.providerBundleIdentifier == Self.providerBundleIdentifier
        }) {
            remember(existing)
            return existing
        }
        let manager = NETunnelProviderManager()
        let proto = NETunnelProviderProtocol()
        proto.providerBundleIdentifier = Self.providerBundleIdentifier
        proto.serverAddress = Self.localizedDescription
        proto.disconnectOnSleep = false
        manager.protocolConfiguration = proto
        manager.localizedDescription = Self.localizedDescription
        manager.isEnabled = true
        // 用户在授权弹窗点“不允许”→ permissionDenied；其他失败（如签名 / 权限配置问题）原样抛出，不误报成权限（#207 E07）。
        do { try await manager.saveToPreferences() } catch { throw Self.permissionMapped(error) }
        // Apple 要求保存后重新 load，否则首次 startVPNTunnel 会失败（NEVPNErrorConfigurationInvalid）。
        try await manager.loadFromPreferences()
        remember(manager)
        return manager
    }

    /// 已存在的 Zephyr VPN 配置（不创建、不弹授权）；没有则 nil。
    func existingManager() async throws -> NETunnelProviderManager? {
        let found = try await NETunnelProviderManager.loadAllFromPreferences().first {
            ($0.protocolConfiguration as? NETunnelProviderProtocol)?.providerBundleIdentifier == Self.providerBundleIdentifier
        }
        remember(found)
        return found
    }

    /// 缓存的 manager：provider 消息每秒一条，每次都 loadAllFromPreferences 是跨进程 IPC，既慢又耗电（REVIEW-Q2 X-P1-3）。
    /// NEVPNConnection 会随系统更新状态，复用同一个 manager 即可；会话不可用时丢弃缓存，下次重新加载。
    private let cacheLock = NSLock()
    private var cachedManager: NETunnelProviderManager?

    private func remember(_ manager: NETunnelProviderManager?) {
        cacheLock.lock(); cachedManager = manager; cacheLock.unlock()
    }

    private func cachedValue() -> NETunnelProviderManager? {
        cacheLock.lock(); defer { cacheLock.unlock() }
        return cachedManager
    }

    private func activeSession() async throws -> NETunnelProviderSession? {
        let cached = cachedValue()
        let manager: NETunnelProviderManager
        if let cached { manager = cached } else if let found = try await existingManager() { manager = found } else { return nil }
        guard let session = manager.connection as? NETunnelProviderSession,
              session.status == .connected || session.status == .reasserting
        else { remember(nil); return nil }
        return session
    }

    private func send(_ request: TunnelRequest, via session: NETunnelProviderSession) async throws -> TunnelResponse {
        guard let data = TunnelMessageCodec.encode(request) else { throw TunnelError.badResponse }
        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<TunnelResponse, Error>) in
            do {
                try session.sendProviderMessage(data) { reply in
                    if let reply, let response = TunnelMessageCodec.decodeResponse(reply) {
                        cont.resume(returning: response)
                    } else {
                        cont.resume(throwing: TunnelError.badResponse)
                    }
                }
            } catch {
                cont.resume(throwing: error)
            }
        }
    }
}

/// 只恢复一次的 continuation（超时与结果谁先到用谁）。
private final class ResumeOnce<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var cont: CheckedContinuation<T?, Never>?
    init(_ cont: CheckedContinuation<T?, Never>) { self.cont = cont }
    func resume(_ value: T?) {
        lock.lock(); let c = cont; cont = nil; lock.unlock()
        c?.resume(returning: value)
    }
}
