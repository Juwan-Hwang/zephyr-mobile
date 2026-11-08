// TunnelController —— 系统 VPN 配置（NETunnelProviderManager）的唯一入口。
//
// - 首次连接时创建 “Zephyr” VPN 配置（系统会弹 VPN 授权；拒绝 → ErrorCode.vpn_permission_denied）。
// - 启动：startVPNTunnel；停止：stopVPNTunnel；模式：写 SharedState.tunnel.mode 并 sendProviderMessage(.setMode)。
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
        let manager = try await loadOrCreateManager()
        if on {
            if !manager.isEnabled {
                manager.isEnabled = true
                try await manager.saveToPreferences()
                try await manager.loadFromPreferences()
            }
            do {
                try manager.connection.startVPNTunnel(options: nil)
            } catch {
                throw TunnelError.permissionDenied
            }
        } else {
            manager.connection.stopVPNTunnel()
        }
        #endif
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

        let enabled = !plan.isEmpty
        // 没有变化就不写系统配置（每次保存都会触发 NEVPNConfigurationChange 通知）。
        let sameRules = (manager.onDemandRules ?? []).count == rules.count
            && zip(manager.onDemandRules ?? [], rules).allSatisfy { type(of: $0) == type(of: $1) && ($0 as? NEOnDemandRuleDisconnect)?.ssidMatch == ($1 as? NEOnDemandRuleDisconnect)?.ssidMatch }
        if manager.isOnDemandEnabled == enabled && sameRules { return }
        manager.onDemandRules = rules.isEmpty ? nil : rules
        manager.isOnDemandEnabled = enabled
        try await manager.saveToPreferences()
        try await manager.loadFromPreferences()
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
        do {
            try await manager.saveToPreferences()
        } catch {
            throw TunnelError.permissionDenied
        }
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
