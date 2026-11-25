// ZephyrPacketTunnelProvider —— Zephyr 的 NEPacketTunnelProvider。
//
// 启动：读 TunnelConfiguration → 打包的地理数据拷进内核目录（BundledGeodata）→ setTunnelNetworkSettings（IPv4/IPv6 默认路由、DNS、MTU）
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
//
// 网络切换（契约 §16.a③ E04）：NWPathMonitor（排除 utun 所在的 .other 接口，看到的是底层物理网络）→ NetworkChangeDetector
// （忽略 reasserting、同一网络上的短暂掉线）→ 去抖 2 s → closeAll（ControllerSocket）+ Darwin `.networkChanged`
// （App 在前台时据此立即跑下一轮场景故障探测）。不重载配置、不重建 TUN；受信任 Wi‑Fi 由系统按需规则自行重评。

import Foundation
import Network
import NetworkExtension
import os

/// 可变状态只在 `queue` 上读写（setState 用锁），系统回调跨线程进入；故以 @unchecked Sendable 声明。
final class ZephyrPacketTunnelProvider: NEPacketTunnelProvider, @unchecked Sendable {

    enum TunnelError: Error, LocalizedError {
        case coreNotLinked
        /// 配置文件不存在 / 为空：还没导入过订阅（例如按需连接在导入前就触发）→ subscription_not_found（契约 §16 ②）。
        case configMissing
        /// 有配置但不能用（不是 UTF-8、缺 fd 哨兵）→ subscription_invalid（契约 §14.x）。
        case configInvalid
        case tunUnavailable
        /// setTunnelNetworkSettings 失败（系统错误原文）。
        case networkSettings(String)
        /// zm_start 的错误原文（如 `geodata missing: …`）。
        case coreFailed(String)
        /// 自动启动被拒：连续失败退避中或已暂停按需，等用户手动连接（ReconnectBackoff）。
        case autoConnectPaused

        var errorDescription: String? {
            switch self {
            case .coreNotLinked: String(localized: "此构建未包含代理核心（libmihomo）。")
            case .configMissing, .configInvalid: String(localized: "没有可用的配置，请先添加订阅。")
            case .tunUnavailable: String(localized: "无法获取虚拟网卡。")
            case .networkSettings(let message): message
            case .coreFailed(let message): String(localized: "代理核心启动失败：\(message)")
            case .autoConnectPaused: String(localized: "自动连接已暂停，请打开 Zephyr 手动连接。")
            }
        }

        /// 对应契约 §10 ErrorCode 的序列化名。
        var code: String {
            switch self {
            case .coreNotLinked, .coreFailed, .autoConnectPaused: "core_crashed"
            case .configMissing: "subscription_not_found"
            case .configInvalid: "subscription_invalid"
            case .tunUnavailable, .networkSettings: "network_unavailable"
            }
        }

        /// 写进 SharedState / 日志页的原文（首页“错误详情”展开显示；`geodata missing:` 据此给专门提示）。
        var detail: String {
            switch self {
            case .coreFailed(let message), .networkSettings(let message): message
            default: errorDescription ?? code
            }
        }
    }

    static let goMemoryLimitBytes: Int64 = 30 * 1024 * 1024
    static let publishInterval: TimeInterval = 5

    private let logger = Logger(subsystem: "com.juwanh.zephyr.PacketTunnel", category: "tunnel")
    private let bridge = MihomoBridge.shared
    private let store = SharedStore.shared
    private let queue = DispatchQueue(label: "com.juwanh.zephyr.PacketTunnel", qos: .utility)

    private let lock = NSLock()
    private var mode: SharedState.Mode = .rule
    private var connectedSince: Date?
    private var lastTraffic = MihomoBridge.Traffic.zero
    private var lastPublish = Date.distantPast
    private var asleep = false
    private var trafficTimer: DispatchSourceTimer?
    private var memoryPressure: DispatchSourceMemoryPressure?
    /// 今日用量账本；只在 `queue` 上读写。
    private var ledger: UsageLedger?
    /// 底层网络监视（§16.a③）；detector 只在 `queue` 上读写。
    private var pathMonitor: NWPathMonitor?
    private var networkDetector = NetworkChangeDetector()
    /// 去抖到点后在独立队列上 closeAll（阻塞 socket 调用不占 `queue`）。
    private let networkDebounce = Debouncer(delay: Debouncer.networkChangeDelay,
                                            queue: DispatchQueue(label: "com.juwanh.zephyr.PacketTunnel.network", qos: .utility))

    // MARK: 生命周期

    override func startTunnel(options: [String: NSObject]?, completionHandler: @escaping (Error?) -> Void) {
        // 起不来的内核不能被按需连接无限次拉起（#1 ②）：手动连接清零；自动启动在退避期 / 已暂停时直接拒绝，不碰内核、不联网。
        if options?[ReconnectBackoff.manualStartOption] != nil {
            ReconnectBackoff.manualStart()
        } else if let wait = autoStartWait() {
            let why = wait < 0 ? "已暂停" : "退避 \(Int(wait)) s"
            logger.notice("startTunnel: 自动连接被拒（\(why, privacy: .public)）")
            return completionHandler(TunnelError.autoConnectPaused)
        }
        ReconnectBackoff.beginAttempt()

        let config = TunnelConfiguration.load(store: store, options: options)
        setState { $0.mode = config.mode }
        publish(status: .connecting, mode: config.mode)

        guard MihomoBridge.isLinked else {
            logger.error("startTunnel: libmihomo 未链接（桩构建），拒绝启动以免流量黑洞")
            return fail(.coreNotLinked, completionHandler)
        }
        guard let mapped = try? MappedFile(url: config.configURL), mapped.count > 0 else {
            return fail(.configMissing, completionHandler)
        }
        guard mapped.looksLikeText else { return fail(.configInvalid, completionHandler) }
        logger.info("startTunnel: config \(mapped.count, privacy: .public) B, mtu \(config.mtu, privacy: .public), ipv6 \(config.ipv6, privacy: .public)")
        let bundledGeodata = prepareGeodata()

        setTunnelNetworkSettings(TunnelNetworkSettingsFactory.make(config)) { [weak self] error in
            guard let self else { return completionHandler(error) }
            if let error {
                self.logger.error("setTunnelNetworkSettings: \(error.localizedDescription, privacy: .public)")
                return self.fail(.networkSettings(error.localizedDescription), completionHandler, underlying: error)
            }
            guard let fd = TunFileDescriptor.resolve(from: self.packetFlow) else {
                return self.fail(.tunUnavailable, completionHandler)
            }
            guard let yaml = String(data: mapped.prefix(mapped.count), encoding: .utf8),
                  let runnable = MihomoBridge.injectingTunFD(yaml, fd: fd) else {
                return self.fail(.configInvalid, completionHandler)
            }
            do {
                self.bridge.setMemoryLimit(bytes: Self.goMemoryLimitBytes)
                // 本地地理数据齐全 → 0（只用本地，绝不在 VPN 起来前联网下载）；不齐 → 默认 15 s 有界下载，失败报 `geodata missing:`。
                let geoTimeout = BundledGeodata.timeoutMillis(bundled: bundledGeodata, extra: MihomoBridge.extraGeodataFiles(yaml),
                                                              home: AppGroup.coreDirectory)
                self.bridge.setGeodataTimeout(ms: geoTimeout)
                self.logger.info("geodata timeout \(geoTimeout, privacy: .public) ms")
                let withMode = MihomoBridge.forcingGeodataLoader(MihomoBridge.settingMode(runnable, config.mode.rawValue))
                try self.bridge.start(homeDir: AppGroup.coreDirectory.path, config: withMode,
                                      controllerSocket: AppGroup.controllerSocketPath)
                self.logger.info("mihomo started: \(self.bridge.version, privacy: .public)")
            } catch MihomoBridge.BridgeError.core(let message) {
                return self.fail(.coreFailed(message), completionHandler)
            } catch {
                return self.fail(.coreFailed(String(describing: error)), completionHandler)
            }
            ReconnectBackoff.reset()
            TunnelFailureLog.clear()
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
        // 睡眠期间停掉 1 Hz 轮询（定时器唤醒会耗电，REVIEW-Q2 X-P1-7）；核心本身保持连接。
        // 取消并在 wake 时重建，而不是 suspend：suspend/resume 不配对或释放已挂起的源会直接崩溃。
        setState { $0.asleep = true }
        nonisolated(unsafe) let done = completionHandler   // NE 允许任意线程回调
        queue.async { [weak self] in
            self?.cancelTrafficTimer()
            done()
        }
    }

    override func wake() {
        setState { $0.asleep = false }
        queue.async { [weak self] in
            guard let self, self.bridge.isRunning, self.trafficTimer == nil else { return }
            self.scheduleTrafficTimer()
        }
    }

    // MARK: 地理数据（契约 §20、docs/geodata.md）

    /// zm_start 前：把 appex 里打包的地理数据拷进内核目录里还没有的位置（不覆盖、临时名 + 改名）。返回打包的文件名。
    private func prepareGeodata() -> [String] {
        let source = BundledGeodata.bundledDirectory()
        let bundled = BundledGeodata.names(in: source)
        if bundled.isEmpty { logger.warning("geodata: 本构建没有打包地理数据（Debug 拉取失败？），缺文件时内核会有界下载") }
        let r = BundledGeodata.installMissing(from: source, into: AppGroup.coreDirectory)
        if !r.copied.isEmpty { logger.info("geodata: 拷入 \(r.copied.joined(separator: ","), privacy: .public)") }
        for (name, why) in r.failed { logger.error("geodata: 拷贝 \(name, privacy: .public) 失败：\(why, privacy: .public)") }
        return bundled
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
            _ = try? store.update { $0.connection.mode = newMode; $0.tunnel.mode = newMode }
            completionHandler?(TunnelMessageCodec.encode(response(.ok)))
        case .urlTest(let file, let url, let timeoutMs):
            // 只接受 core 目录下的纯文件名，防路径穿越。
            guard !file.contains("/"), !file.hasPrefix("."),
                  let json = try? String(contentsOf: AppGroup.coreDirectory.appendingPathComponent(file), encoding: .utf8) else {
                var r = response(.failed); r.errorCode = "internal"
                completionHandler?(TunnelMessageCodec.encode(r))
                return
            }
            let bridge = self.bridge
            nonisolated(unsafe) let reply = completionHandler   // NE 允许任意线程回调
            DispatchQueue.global(qos: .utility).async { [weak self] in
                let out = bridge.urlTest(proxiesJSON: json, url: url, timeoutMs: timeoutMs, concurrency: 8)
                guard let self else { reply?(nil); return }
                var r = self.response(.ok); r.payload = out
                reply?(TunnelMessageCodec.encode(r))
            }
        case .logs(let since, let minLevel, let limit):
            var r = response(.ok)
            r.payload = bridge.logs(since: since, minLevel: minLevel, limit: max(1, min(limit, 500)))
            completionHandler?(TunnelMessageCodec.encode(r))
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
                try bridge.reload(config: MihomoBridge.forcingGeodataLoader(MihomoBridge.settingMode(runnable, currentMode.rawValue)))
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
        queue.async { [weak self] in
            var l = UsageLedger.load() ?? .empty(Date())
            l.tunnelStarted()
            self?.ledger = l
        }
        queue.async { [weak self] in self?.scheduleTrafficTimer() }

        let pressure = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical], queue: queue)
        pressure.setEventHandler { [weak self] in
            guard let self else { return }
            self.logger.warning("memory pressure: footprint \(MemoryFootprint.current() ?? -1, privacy: .public) B")
            self.bridge.freeOSMemory()
        }
        pressure.resume()
        memoryPressure = pressure

        startPathMonitor()
    }

    private func stopMonitors() {
        queue.async { [weak self] in self?.cancelTrafficTimer() }
        memoryPressure?.cancel(); memoryPressure = nil
        stopPathMonitor()
    }

    // MARK: 网络切换（§16.a③）

    private func startPathMonitor() {
        stopPathMonitor()
        // 排除 .other（utun 自己）：否则默认路径永远是隧道接口，看不到 Wi‑Fi ↔ 蜂窝。
        let monitor = NWPathMonitor(prohibitedInterfaceTypes: [.other])
        monitor.pathUpdateHandler = { [weak self] path in
            // 回调就在 `queue` 上（start(queue:)）。
            self?.handlePathUpdate(Self.fingerprint(path))
        }
        queue.async { [weak self] in self?.networkDetector.reset() }
        monitor.start(queue: queue)
        pathMonitor = monitor
    }

    private func stopPathMonitor() {
        pathMonitor?.cancel(); pathMonitor = nil
        networkDebounce.cancel()
    }

    /// 只在 `queue` 上调用。
    private func handlePathUpdate(_ fp: NetworkFingerprint) {
        // reasserting：同一网络上的短暂重连，不算网络变化（§16.a③）。
        guard networkDetector.observe(fp, reasserting: reasserting) else { return }
        logger.info("network changed: \(fp.primaryInterface ?? "-", privacy: .public)")
        networkDebounce.schedule { [weak self] in
            guard let self, self.bridge.isRunning else { return }
            let ok = ControllerSocket.closeAllConnections(socketPath: AppGroup.controllerSocketPath)
            self.logger.info("network changed: closeAll \(ok ? "ok" : "failed", privacy: .public)")
            DarwinNotifier.post(.networkChanged)
        }
    }

    static func fingerprint(_ path: NWPath) -> NetworkFingerprint {
        let primary = path.availableInterfaces.first { $0.type != .other && $0.type != .loopback }
        return NetworkFingerprint(
            satisfied: path.status == .satisfied,
            primaryInterface: primary.map { "\(Self.name($0.type)):\($0.name)" },
            gateways: path.gateways.map { "\($0)" }
        )
    }

    private static func name(_ t: NWInterface.InterfaceType) -> String {
        switch t {
        case .wifi: "wifi"
        case .cellular: "cellular"
        case .wiredEthernet: "wiredEthernet"
        case .loopback: "loopback"
        case .other: "other"
        @unknown default: "unknown"
        }
    }

    /// 只在 `queue` 上调用。
    private func scheduleTrafficTimer() {
        trafficTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 1, repeating: 1, leeway: .milliseconds(250))
        timer.setEventHandler { [weak self] in self?.tick() }
        timer.resume()
        trafficTimer = timer
    }

    /// 只在 `queue` 上调用。
    private func cancelTrafficTimer() {
        trafficTimer?.cancel()
        trafficTimer = nil
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
        _ = try? store.update { $0.rate.push(down: traffic.down, up: traffic.up, at: now) }
        if var l = ledger {
            l.record(total: traffic.upTotal + traffic.downTotal, at: now)
            l.save()
            ledger = l
        }
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

    private func publish(status: SharedState.Status, mode: SharedState.Mode, since: Date? = nil, errorCode: String? = nil,
                         errorMessage: String? = nil) {
        _ = try? store.update {
            $0.connection = SharedState.Connection(status: status, mode: mode, since: since, errorCode: errorCode,
                                                   errorMessage: errorMessage)
            if status != .connected { $0.rate.downBps = 0; $0.rate.upBps = 0 }
        }
        DarwinNotifier.post(.tunnelStatus)
    }

    /// 启动失败：原因写进 SharedState（首页错误详情）与失败日志文件（日志页），再按 ReconnectBackoff 决定暂停按需 / 退避。
    private func fail(_ error: TunnelError, _ completion: (Error?) -> Void, underlying: Error? = nil) {
        let detail = error.detail
        logger.error("startTunnel failed: \(error.code, privacy: .public) \(detail, privacy: .public)")
        publish(status: .failed, mode: currentMode, errorCode: error.code, errorMessage: detail)
        // 内核缓冲里启动失败前后的日志（扩展进程马上退出，App 之后读不到 zm_logs）+ 失败原因本身。
        TunnelFailureLog.save(coreLogsJSON: bridge.logs(since: 0, minLevel: "info", limit: 60),
                              failure: "\(error.code): \(detail)", at: Date())
        let outcome = ReconnectBackoff.onFailure(code: error.code, message: detail, failures: ReconnectBackoff.streak().failures)
        if outcome.pause {
            ReconnectBackoff.pause()
            logger.notice("按需连接已暂停，等下次手动连接")
        } else if outcome.retryAfter == nil {
            ReconnectBackoff.reset()   // 不归内核的失败：不退避
        }
        DarwinNotifier.post(.tunnelStatus)
        completion(underlying ?? error)
    }

    /// 自动启动（系统按需 / 系统设置里的开关）前：还要等多少秒；-1 = 已暂停；nil = 可以启动。
    private func autoStartWait() -> TimeInterval? {
        let s = ReconnectBackoff.streak()
        guard let wait = ReconnectBackoff.waitBeforeAuto(s, now: Date()) else {
            if !s.paused { ReconnectBackoff.pause() }   // 连续失败用尽（含启动中途被杀的那几次）
            return -1
        }
        return wait > 0 ? wait : nil
    }
}
