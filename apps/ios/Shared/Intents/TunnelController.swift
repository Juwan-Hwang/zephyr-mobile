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

    enum TunnelError: Error, Sendable {
        case permissionDenied
        case notConnected
        case badResponse
    }

    // MARK: ConnectionControlling

    func setConnected(_ on: Bool) async throws {
        #if targetEnvironment(simulator)
        try PendingCommandChannel.post(.setConnected(on))
        #else
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

    // MARK: 内部

    func loadOrCreateManager() async throws -> NETunnelProviderManager {
        let managers = try await NETunnelProviderManager.loadAllFromPreferences()
        if let existing = managers.first(where: {
            ($0.protocolConfiguration as? NETunnelProviderProtocol)?.providerBundleIdentifier == Self.providerBundleIdentifier
        }) {
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
        return manager
    }

    /// 已存在的 Zephyr VPN 配置（不创建、不弹授权）；没有则 nil。
    func existingManager() async throws -> NETunnelProviderManager? {
        try await NETunnelProviderManager.loadAllFromPreferences().first {
            ($0.protocolConfiguration as? NETunnelProviderProtocol)?.providerBundleIdentifier == Self.providerBundleIdentifier
        }
    }

    private func activeSession() async throws -> NETunnelProviderSession? {
        let managers = try await NETunnelProviderManager.loadAllFromPreferences()
        guard let manager = managers.first(where: {
            ($0.protocolConfiguration as? NETunnelProviderProtocol)?.providerBundleIdentifier == Self.providerBundleIdentifier
        }), let session = manager.connection as? NETunnelProviderSession,
              session.status == .connected || session.status == .reasserting
        else { return nil }
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
