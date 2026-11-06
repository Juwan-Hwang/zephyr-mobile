// ZephyrPacketTunnelProvider —— Zephyr 的 NEPacketTunnelProvider。
//
// 启动：读 TunnelConfiguration → setTunnelNetworkSettings（IPv4/IPv6 默认路由、DNS、MTU）
//       → 取 utun fd（TunFileDescriptor）→ 把 App 生成的配置里的 fd 哨兵换成真实 fd → MihomoBridge.start。
//       mihomo 以静态库在本进程运行，禁止 Process()。控制口 external-controller-unix 在 App Group（App 读策略组/连接）。
// 状态：写 SharedState.connection / rate（SharedStore 原子写 + Darwin 通知），App、小组件、控制中心据此刷新。
// 消息：handleAppMessage 支持 TunnelRequest（status / traffic / setMode / reloadConfig）。
//
// 内存预算（jetsam 上限约 50 MB，超出即被杀、VPN 断开）：
//   - 本进程只链接 NetworkExtension + Foundation，不链接 SwiftUI / ZephyrDesign / ZephyrFeatures。
//   - Go 运行时软上限 30 MB（zm_set_memory_limit），给 Swift、NE 框架、包缓冲留余量。
//   - 配置 / 编译后的规则集 / GeoIP 一律由核心 mmap 只读映射（文件背书的干净页，可被系统回收，不计 dirty footprint）；
//     Swift 侧需要窥探配置时用 MappedFile，绝不 Data(contentsOf:) 整份读入。
//   - 收到内存压力（DispatchSource.memoryPressure）立即 zm_free_os_memory()。
//   - 流量轮询 1 Hz，只保留一个最新值；共享文件每 5 秒最多写一次。

import Foundation
import NetworkExtension
import os

final class ZephyrPacketTunnelProvider: NEPacketTunnelProvider {

    enum TunnelError: Error, LocalizedError {
        case coreNotLinked
        case configMissing
        case tunUnavailable
        case coreFailed(String)

        var errorDescription: String? {
            switch self {
            case .coreNotLinked: "此构建未包含代理核心（libmihomo）。"
            case .configMissing: "没有可用的配置，请先添加订阅。"
            case .tunUnavailable: "无法获取虚拟网卡。"
            case .coreFailed(let message): "代理核心启动失败：\(message)"
            }
        }

        /// 对应契约 §10 ErrorCode 的序列化名。
        var code: String {
            switch self {
            case .coreNotLinked, .coreFailed: "core_crashed"
            case .configMissing: "subscription_invalid"
            case .tunUnavailable: "network_unavailable"
            }
        }
    }

    static let goMemoryLimitBytes: Int64 = 30 * 1024 * 1024
    static let publishInterval: TimeInterval = 5

    private let logger = Logger(subsystem: "app.zephyr.mobile.PacketTunnel", category: "tunnel")
    private let bridge = MihomoBridge.shared
    private let store = SharedStore.shared
    private let queue = DispatchQueue(label: "app.zephyr.mobile.PacketTunnel", qos: .utility)

    private let lock = NSLock()
    private var mode: SharedState.Mode = .rule
    private var connectedSince: Date?
    private var lastTraffic = MihomoBridge.Traffic.zero
    private var lastPublish = Date.distantPast
    private var asleep = false
    private var trafficTimer: DispatchSourceTimer?
    private var memoryPressure: DispatchSourceMemoryPressure?

    // MARK: 生命周期

    override func startTunnel(options: [String: NSObject]?, completionHandler: @escaping (Error?) -> Void) {
        let config = TunnelConfiguration.load(store: store, options: options)
        setState { $0.mode = config.mode }
        publish(status: .connecting, mode: config.mode)

        guard MihomoBridge.isLinked else {
            logger.error("startTunnel: libmihomo 未链接（桩构建），拒绝启动以免流量黑洞")
            return fail(.coreNotLinked, completionHandler)
        }
        guard let mapped = try? MappedFile(url: config.configURL), mapped.count > 0, mapped.looksLikeText else {
            return fail(.configMissing, completionHandler)
        }
        logger.info("startTunnel: config \(mapped.count, privacy: .public) B, mtu \(config.mtu, privacy: .public), ipv6 \(config.ipv6, privacy: .public)")

        setTunnelNetworkSettings(TunnelNetworkSettingsFactory.make(config)) { [weak self] error in
            guard let self else { return completionHandler(error) }
            if let error {
                self.logger.error("setTunnelNetworkSettings: \(error.localizedDescription, privacy: .public)")
                self.publish(status: .failed, mode: config.mode, errorCode: "network_unavailable")
                return completionHandler(error)
            }
            guard let fd = TunFileDescriptor.resolve(from: self.packetFlow) else {
                return self.fail(.tunUnavailable, completionHandler)
            }
            guard let yaml = String(data: mapped.prefix(mapped.count), encoding: .utf8),
                  let runnable = MihomoBridge.injectingTunFD(yaml, fd: fd) else {
                return self.fail(.configMissing, completionHandler)
            }
            do {
                self.bridge.setMemoryLimit(bytes: Self.goMemoryLimitBytes)
                let withMode = MihomoBridge.settingMode(runnable, config.mode.rawValue)
                try self.bridge.start(homeDir: AppGroup.coreDirectory.path, config: withMode,
                                      controllerSocket: AppGroup.controllerSocketPath)
                self.logger.info("mihomo started: \(self.bridge.version, privacy: .public)")
            } catch {
                return self.fail(.coreFailed(String(describing: error)), completionHandler)
            }
            let now = Date()
            self.setState { $0.connectedSince = now }
            self.publish(status: .connected, mode: config.mode, since: now)
            self.startMonitors()
            completionHandler(nil)
        }
    }

    override func stopTunnel(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        logger.info("stopTunnel: reason \(reason.rawValue, privacy: .public)")
        stopMonitors()
        bridge.stop()
        setState { $0.connectedSince = nil; $0.lastTraffic = .zero }
        publish(status: .disconnected, mode: currentMode)
        completionHandler()
    }

    override func sleep(completionHandler: @escaping () -> Void) {
        // 睡眠期间跳过轮询与写盘，省电；核心本身保持连接。
        //（不 suspend DispatchSource：suspend/resume 不配对或释放已挂起的源会直接崩溃。）
        setState { $0.asleep = true }
        completionHandler()
    }

    override func wake() {
        setState { $0.asleep = false }
    }

    // MARK: App 消息

    override func handleAppMessage(_ messageData: Data, completionHandler: ((Data?) -> Void)?) {
        guard let request = TunnelMessageCodec.decodeRequest(messageData) else {
            completionHandler?(TunnelMessageCodec.encode(response(.unsupported)))
            return
        }
        switch request {
        case .status, .traffic:
            completionHandler?(TunnelMessageCodec.encode(response(.ok)))
        case .setMode(let newMode):
            do { try bridge.setMode(newMode.rawValue) } catch {
                var r = response(.failed); r.errorCode = "core_crashed"
                completionHandler?(TunnelMessageCodec.encode(r))
                return
            }
            setState { $0.mode = newMode }
            try? store.update { $0.connection.mode = newMode; $0.tunnel.mode = newMode }
            completionHandler?(TunnelMessageCodec.encode(response(.ok)))
        case .reloadConfig:
            // App 重新生成了配置（订阅更新 / 场景切换需重载）：重新注入当前 fd 后热重载。
            let config = TunnelConfiguration.load(store: store)
            guard let fd = TunFileDescriptor.resolve(from: packetFlow),
                  let mapped = try? MappedFile(url: config.configURL),
                  let yaml = String(data: mapped.prefix(mapped.count), encoding: .utf8),
                  let runnable = MihomoBridge.injectingTunFD(yaml, fd: fd) else {
                var r = response(.failed); r.errorCode = "subscription_invalid"
                completionHandler?(TunnelMessageCodec.encode(r))
                return
            }
            do {
                try bridge.reload(config: MihomoBridge.settingMode(runnable, currentMode.rawValue))
                completionHandler?(TunnelMessageCodec.encode(response(.ok)))
            } catch {
                var r = response(.failed); r.errorCode = "core_crashed"
                completionHandler?(TunnelMessageCodec.encode(r))
            }
        }
    }

    // MARK: 监控

    private func startMonitors() {
        stopMonitors()
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 1, repeating: 1, leeway: .milliseconds(250))
        timer.setEventHandler { [weak self] in self?.tick() }
        timer.resume()
        trafficTimer = timer

        let pressure = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical], queue: queue)
        pressure.setEventHandler { [weak self] in
            guard let self else { return }
            self.logger.warning("memory pressure: footprint \(MemoryFootprint.current() ?? -1, privacy: .public) B")
            self.bridge.freeOSMemory()
        }
        pressure.resume()
        memoryPressure = pressure
    }

    private func stopMonitors() {
        trafficTimer?.cancel(); trafficTimer = nil
        memoryPressure?.cancel(); memoryPressure = nil
    }

    private func tick() {
        var asleep = false
        setState { asleep = $0.asleep }
        guard !asleep else { return }
        let traffic = bridge.traffic()
        let now = Date()
        var shouldPublish = false
        setState {
            $0.lastTraffic = traffic
            if now.timeIntervalSince($0.lastPublish) >= Self.publishInterval {
                $0.lastPublish = now
                shouldPublish = true
            }
        }
        guard shouldPublish else { return }
        try? store.update { $0.rate.push(down: traffic.down, up: traffic.up, at: now) }
    }

    // MARK: 状态

    private struct State {
        var mode: SharedState.Mode
        var connectedSince: Date?
        var lastTraffic: MihomoBridge.Traffic
        var lastPublish: Date
        var asleep: Bool
    }

    private func setState(_ body: (inout State) -> Void) {
        lock.lock(); defer { lock.unlock() }
        var s = State(mode: mode, connectedSince: connectedSince, lastTraffic: lastTraffic, lastPublish: lastPublish, asleep: asleep)
        body(&s)
        mode = s.mode; connectedSince = s.connectedSince; lastTraffic = s.lastTraffic; lastPublish = s.lastPublish; asleep = s.asleep
    }

    private var currentMode: SharedState.Mode { lock.lock(); defer { lock.unlock() }; return mode }

    private func response(_ result: TunnelResponse.Result) -> TunnelResponse {
        lock.lock(); defer { lock.unlock() }
        return TunnelResponse(
            result: result,
            status: bridge.isRunning ? .connected : .disconnected,
            mode: mode,
            since: connectedSince,
            upBps: lastTraffic.up,
            downBps: lastTraffic.down,
            upTotal: lastTraffic.upTotal,
            downTotal: lastTraffic.downTotal,
            residentBytes: MemoryFootprint.current(),
            errorCode: nil
        )
    }

    private func publish(status: SharedState.Status, mode: SharedState.Mode, since: Date? = nil, errorCode: String? = nil) {
        try? store.update {
            $0.connection = SharedState.Connection(status: status, mode: mode, since: since, errorCode: errorCode)
            if status != .connected { $0.rate.downBps = 0; $0.rate.upBps = 0 }
        }
        DarwinNotifier.post(.tunnelStatus)
    }

    private func fail(_ error: TunnelError, _ completion: (Error?) -> Void) {
        logger.error("startTunnel failed: \(error.code, privacy: .public)")
        publish(status: .failed, mode: currentMode, errorCode: error.code)
        completion(error)
    }
}
