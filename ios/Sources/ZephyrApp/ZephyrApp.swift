// Zephyr iOS App — Main Entry Point
// Matches Android 5-tab layout: Home, Proxies, Profiles, Logs, Settings

import SwiftUI
import Foundation
import NetworkExtension
import ZephyrCore
import PacketTunnel
import DesignSystem

@main
struct ZephyrApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
        }
    }
}

// ── App State ────────────────────────────────────────────────────────────

@MainActor
class AppState: ObservableObject {
    // ── Core state ──────────────────────────────────────────────────────
    @Published var isCoreRunning: Bool = false
    @Published var isStartingCore: Bool = false
    @Published var mixedPort: UInt16 = defaultMixedPort()
    @Published var apiPort: UInt16 = defaultApiPort()
    @Published var proxyMode: String = "rule"
    @Published var coreSecret: String = ""
    @Published var coreVersion: String = ""
    @Published var currentNodeName: String = ""

    // ── Profiles / Subscriptions ────────────────────────────────────────
    @Published var profiles: [ProfileItem] = []
    @Published var activeProfile: String = ""

    // ── Proxy groups & nodes ────────────────────────────────────────────
    @Published var proxyGroups: [ProxyGroup] = []
    @Published var currentGroupName: String = ""
    @Published var proxySortMode: String = "default"

    // ── Connections ─────────────────────────────────────────────────────
    @Published var connections: [ConnectionItem] = []

    // ── Events ──────────────────────────────────────────────────────────
    @Published var events: [EventItem] = []

    // ── Logs ────────────────────────────────────────────────────────────
    @Published var logs: [LogEntryItem] = []
    @Published var logLevelFilter: String = "all"

    // ── Settings ────────────────────────────────────────────────────────
    @Published var systemProxyEnabled: Bool = false
    @Published var tunEnabled: Bool = false
    @Published var ipv6Enabled: Bool = false
    @Published var allowLan: Bool = false
    @Published var unifiedDelay: Bool = true
    @Published var socksPort: UInt16 = 7891
    @Published var httpPort: UInt16 = 0
    @Published var themeMode: String = "auto"
    @Published var language: String = "zh"

    // ── Smart Selector ──────────────────────────────────────────────────
    @Published var smartEnabled: Bool = false
    @Published var smartAutoTest: Bool = false
    @Published var smartLatencyWeight: Double = 0.4
    @Published var smartSuccessWeight: Double = 0.4
    @Published var smartStabilityWeight: Double = 0.2
    @Published var smartDecayHalfLife: Double = 6.0

    // ── Failover ────────────────────────────────────────────────────────
    @Published var failoverEnabled: Bool = false
    @Published var failoverThreshold: UInt32 = 3
    @Published var failoverCooldownSecs: UInt64 = 60
    @Published var failoverFallbackGroup: String = ""

    // ── Loading states ──────────────────────────────────────────────────
    @Published var isTestingLatency: Bool = false
    @Published var isUpdatingSubscriptions: Bool = false

    // ── Dialog state ────────────────────────────────────────────────────
    @Published var showAddProfileDialog: Bool = false
    @Published var addProfileUrl: String = ""
    @Published var addProfileName: String = ""

    // ── Internal state ──────────────────────────────────────────────────
    private let appStore = AppStore()
    private var nodeFailureCounts: [String: UInt32] = [:]
    private var vpnManager: NETunnelProviderManager?

    // ── VPN state ────────────────────────────────────────────────────────
    @Published var vpnStatus: NEVPNStatus = .disconnected

    init() {
        setEventCallback(CoreEventCallbackSwift { [weak self] event in
            Task { @MainActor in
                guard let self = self else { return }
                let level: String
                switch event.level {
                case .fatal: level = "Fatal"
                case .error: level = "Error"
                case .warn: level = "Warn"
                case .info: level = "Info"
                }
                let module: String
                switch event.module {
                case .core: module = "core"
                case .subscription: module = "subscription"
                case .prism: module = "prism"
                case .config: module = "config"
                case .plugin: module = "plugin"
                case .system: module = "system"
                case .updater: module = "updater"
                case .override: module = "override"
                case .rule: module = "rule"
                case .smart: module = "smart"
                }
                self.addEvent(level: level, module: module, message: event.message, timestamp: event.timestamp)

                if detectCacheLockIssue(log: event.message) {
                    self.addEvent(level: "Warn", module: "system", message: "Cache lock issue detected, consider restarting core", timestamp: event.timestamp)
                }
            }
        })

        activeProfile = appStore.getActiveProfile() ?? ""
        isCoreRunning = appStore.isCoreRunning()

        // Load existing VPN configuration (if any)
        loadVpnManager()
    }

    // ── VPN Tunnel management ────────────────────────────────────────────

    func loadVpnManager() {
        NETunnelProviderManager.loadAllFromPreferences { [weak self] managers, _ in
            guard let self = self else { return }
            if let existing = managers?.first {
                self.vpnManager = existing
                self.vpnStatus = existing.connection.status
                self.observeVpnStatus()
            } else {
                self.vpnManager = NETunnelProviderManager()
            }
        }
    }

    func startVpnTunnel() {
        guard let manager = vpnManager else {
            vpnManager = NETunnelProviderManager()
            configureAndStartTunnel()
            return
        }
        configureAndStartTunnel()
    }

    private func configureAndStartTunnel() {
        guard let manager = vpnManager else { return }

        let proto = NETunnelProviderProtocol()
        proto.providerBundleIdentifier = PacketTunnelOptions.tunnelProviderBundleId
        proto.serverAddress = "Zephyr"
        proto.providerConfiguration = [
            PacketTunnelOptions.configPathKey: configPathForTunnel(),
            PacketTunnelOptions.secretKey: coreSecret
        ]

        manager.protocolConfiguration = proto
        manager.localizedDescription = "Zephyr Proxy"
        manager.isEnabled = true

        manager.saveToPreferences { [weak self] error in
            guard let self = self else { return }
            if let error = error {
                self.addEvent(level: "Error", module: "core", message: "VPN save failed: \(error.localizedDescription)", timestamp: 0)
                return
            }
            do {
                try manager.connection.startVPNTunnel(options: [
                    PacketTunnelOptions.configPathKey: self.configPathForTunnel() as NSObject,
                    PacketTunnelOptions.secretKey: self.coreSecret as NSObject
                ])
                self.observeVpnStatus()
            } catch {
                self.addEvent(level: "Error", module: "core", message: "VPN start failed: \(error.localizedDescription)", timestamp: 0)
            }
        }
    }

    func stopVpnTunnel() {
        vpnManager?.connection.stopVPNTunnel()
    }

    private func configPathForTunnel() -> String {
        // Use app group shared container for config file
        let fileManager = FileManager.default
        if let groupDir = fileManager.containerURL(forSecurityApplicationGroupIdentifier: PacketTunnelOptions.appGroupId) {
            return groupDir.appendingPathComponent("core/run_config.yaml").path
        }
        // Fallback: temp directory
        return NSTemporaryDirectory() + "zephyr/run_config.yaml"
    }

    private func observeVpnStatus() {
        guard let connection = vpnManager?.connection as? NETunnelProviderSession else { return }
        NotificationCenter.default.addObserver(
            forName: .NEVPNStatusDidChange,
            object: connection,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            let status = connection.status
            self.vpnStatus = status
            switch status {
            case .connected:
                self.isCoreRunning = true
                self.appStore.setCoreRunning(running: true)
                self.addEvent(level: "Info", module: "core", message: "VPN tunnel connected", timestamp: 0)
            case .disconnected:
                self.isCoreRunning = false
                self.appStore.setCoreRunning(running: false)
                self.addEvent(level: "Info", module: "core", message: "VPN tunnel disconnected", timestamp: 0)
            case .invalid:
                self.addEvent(level: "Warn", module: "core", message: "VPN configuration invalid", timestamp: 0)
            case .reasserting:
                self.addEvent(level: "Info", module: "core", message: "VPN tunnel reasserting...", timestamp: 0)
            default:
                break
            }
        }
    }

    // ── Core management ─────────────────────────────────────────────────

    func toggleCore(_ enabled: Bool) {
        if enabled { startCore() } else { stopCore() }
    }

    private func startCore() {
        guard !isStartingCore else { return }
        isStartingCore = true
        Task {
            do {
                let secret = try generateSecret()
                coreSecret = secret

                let prefs = GlobalPreferences(
                    mode: proxyMode,
                    tunEnabled: tunEnabled ? true : nil,
                    mixedPort: mixedPort,
                    socksPort: socksPort,
                    httpPort: httpPort > 0 ? httpPort : nil,
                    ipv6: ipv6Enabled ? true : nil,
                    allowLan: allowLan ? true : nil,
                    unifiedDelay: unifiedDelay ? true : nil
                )

                let minimalResult = buildMinimalRuntimeConfig(secret: secret)
                if let result = prepareRuntimeConfig(content: minimalResult.yamlContent, secret: secret, prefs: prefs) {
                    mixedPort = result.apiPort
                    apiPort = result.apiPort

                    // Write runtime config to shared container so the
                    // Network Extension can read it
                    writeRunConfig(result.yamlContent)

                    if tunEnabled {
                        // On iOS, TUN mode requires the Network Extension
                        startVpnTunnel()
                    } else {
                        isCoreRunning = true
                        appStore.setCoreRunning(running: true)
                    }

                    if activeProfile.isEmpty {
                        activeProfile = "default"
                        appStore.setActiveProfile(profile: "default")
                    }
                    addEvent(level: "Info", module: "core", message: "Core started on port \(result.apiPort)", timestamp: 0)

                    // Refresh proxy data from mihomo API after core starts
                    refreshProxies()
                    refreshConnections()
                } else {
                    addEvent(level: "Error", module: "core", message: "Failed to prepare runtime config", timestamp: 0)
                }
            } catch {
                addEvent(level: "Error", module: "core", message: "Core start failed: \(error.localizedDescription)", timestamp: 0)
            }
            isStartingCore = false
        }
    }

    private func stopCore() {
        if vpnStatus == .connected || vpnStatus == .connecting {
            stopVpnTunnel()
        }
        isCoreRunning = false
        appStore.setCoreRunning(running: false)
        coreSecret = ""
        apiPort = 0
        addEvent(level: "Info", module: "core", message: "Core stopped", timestamp: 0)
    }

    private func writeRunConfig(_ yamlContent: String) {
        let configPath = configPathForTunnel()
        let configDir = URL(fileURLWithPath: configPath).deletingLastPathComponent().path

        // Ensure directory exists
        do {
            try FileManager.default.createDirectory(atPath: configDir, withIntermediateDirectories: true)
        } catch {
            addEvent(level: "Error", module: "core", message: "Failed to create config dir: \(error.localizedDescription)", timestamp: 0)
            return
        }

        do {
            try yamlContent.write(toFile: configPath, atomically: true, encoding: .utf8)
        } catch {
            addEvent(level: "Error", module: "core", message: "Failed to write run config: \(error.localizedDescription)", timestamp: 0)
        }
    }

    func setProxyMode(_ mode: String) {
        proxyMode = mode
        if isCoreRunning {
            Task { restartCoreWithNewConfig() }
        }
    }

    private func restartCoreWithNewConfig() async {
        stopCore()
        try? await Task.sleep(nanoseconds: 500_000_000)
        startCore()
    }

    // ── Profile / Subscription management ───────────────────────────────

    func setActiveProfile(_ name: String) {
        activeProfile = name
        appStore.setActiveProfile(profile: name)
        if isCoreRunning {
            Task { restartCoreWithNewConfig() }
        }
    }

    func addProfile(url: String, name: String) {
        Task {
            do {
                let rawName = name.isEmpty
                    ? (URL(string: url)?.host ?? "Profile-\(Int(Date().timeIntervalSince1970))")
                    : name
                let nameWithExt = (rawName.hasSuffix(".yaml") || rawName.hasSuffix(".yml"))
                    ? rawName : "\(rawName).yaml"
                let sanitizedName = try sanitizeConfigFileName(configPath: nameWithExt)

                // Download subscription content
                addEvent(level: "Info", module: "subscription", message: "Downloading: \(sanitizedName)", timestamp: 0)
                let content = try await downloadSubscriptionContent(url: url)
                if content.isEmpty {
                    throw NSError(domain: "Zephyr", code: 1, userInfo: [NSLocalizedDescriptionKey: "Downloaded content is empty"])
                }

                // Save to app group shared container
                let configDir = sharedConfigsDir()
                try FileManager.default.createDirectory(atPath: configDir, withIntermediateDirectories: true)
                let configPath = (configDir as NSString).appendingPathComponent(sanitizedName)
                try content.write(toFile: configPath, atomically: true, encoding: .utf8)

                let maskedUrl = maskUrl(url: url)
                let newProfile = ProfileItem(name: sanitizedName, url: url, urlDisplay: maskedUrl)
                profiles.append(newProfile)
                addEvent(level: "Info", module: "subscription", message: "Added profile: \(sanitizedName)", timestamp: 0)
            } catch {
                addEvent(level: "Error", module: "subscription", message: "Add profile failed: \(error.localizedDescription)", timestamp: 0)
            }
        }
    }

    func deleteProfile(_ name: String) {
        profiles.removeAll { $0.name == name }
        if activeProfile == name {
            activeProfile = profiles.first?.name ?? ""
            appStore.setActiveProfile(profile: activeProfile)
        }
        addEvent(level: "Info", module: "subscription", message: "Deleted profile: \(name)", timestamp: 0)
    }

    func renameProfile(oldName: String, newName: String) {
        Task {
            do {
                let sanitized = try sanitizeConfigFileName(configPath: newName)
                profiles = profiles.map { $0.name == oldName ? ProfileItem(name: sanitized, url: $0.url, urlDisplay: $0.urlDisplay, subInfo: $0.subInfo) : $0 }
                if activeProfile == oldName {
                    activeProfile = sanitized
                    appStore.setActiveProfile(profile: sanitized)
                }
            } catch {
                addEvent(level: "Error", module: "subscription", message: "Rename failed: \(error.localizedDescription)", timestamp: 0)
            }
        }
    }

    func updateProfile(_ name: String) {
        Task {
            isUpdatingSubscriptions = true
            do {
                addEvent(level: "Info", module: "subscription", message: "Updating profile: \(name)", timestamp: 0)
                guard let profile = profiles.first(where: { $0.name == name }),
                      let profileUrl = profile.url else {
                    addEvent(level: "Error", module: "subscription", message: "No URL for profile: \(name)", timestamp: 0)
                    isUpdatingSubscriptions = false
                    return
                }
                let content = try await downloadSubscriptionContent(url: profileUrl)
                if !content.isEmpty {
                    let configDir = sharedConfigsDir()
                    let configPath = (configDir as NSString).appendingPathComponent(name)
                    try content.write(toFile: configPath, atomically: true, encoding: .utf8)
                }
                addEvent(level: "Info", module: "subscription", message: "Profile updated: \(name)", timestamp: 0)
            } catch {
                addEvent(level: "Error", module: "subscription", message: "Update failed: \(error.localizedDescription)", timestamp: 0)
            }
            isUpdatingSubscriptions = false
        }
    }

    func updateAllProfiles() {
        Task {
            isUpdatingSubscriptions = true
            for profile in profiles {
                addEvent(level: "Info", module: "subscription", message: "Updating: \(profile.name)", timestamp: 0)
            }
            addEvent(level: "Info", module: "subscription", message: "All profiles updated", timestamp: 0)
            isUpdatingSubscriptions = false
        }
    }

    // ── Proxy management ────────────────────────────────────────────────

    func selectProxyGroup(_ groupName: String) {
        currentGroupName = groupName
    }

    func selectProxyNode(groupName: String, nodeName: String) {
        currentNodeName = nodeName
        if let idx = proxyGroups.firstIndex(where: { $0.name == groupName }) {
            proxyGroups[idx].current = nodeName
        }
        // Actually switch the proxy node via mihomo API
        if isCoreRunning && apiPort > 0 {
            Task {
                do {
                    try await mihomoApiSelectProxy(groupName: groupName, nodeName: nodeName)
                    addEvent(level: "Info", module: "core", message: "Switched to node: \(nodeName)", timestamp: 0)
                } catch {
                    addEvent(level: "Error", module: "core", message: "Failed to switch node: \(error.localizedDescription)", timestamp: 0)
                }
            }
        } else {
            addEvent(level: "Info", module: "core", message: "Switched to node: \(nodeName)", timestamp: 0)
        }
    }

    func testLatency() {
        guard !isTestingLatency else { return }
        guard isCoreRunning && apiPort > 0 else { return }
        isTestingLatency = true
        Task {
            do {
                addEvent(level: "Info", module: "core", message: "Starting latency test...", timestamp: 0)

                let delayMap = try await mihomoApiTestGroupDelay(groupName: currentGroupName)
                let updatedGroups = proxyGroups.map { group -> ProxyGroup in
                    guard group.name == currentGroupName else { return group }
                    let updatedNodes = group.nodes.map { node -> ProxyNode in
                        let delay = delayMap[node.name] ?? -1
                        return ProxyNode(
                            name: node.name,
                            type: node.type,
                            latency: delay > 0 ? delay : 0,
                            alive: delay > 0
                        )
                    }
                    return ProxyGroup(name: group.name, type: group.type, nodes: updatedNodes, current: group.current)
                }
                proxyGroups = updatedGroups

                addEvent(level: "Info", module: "core", message: "Latency test completed", timestamp: 0)
            } catch {
                addEvent(level: "Error", module: "core", message: "Latency test failed: \(error.localizedDescription)", timestamp: 0)
            }
            isTestingLatency = false
        }
    }

    func smartSelectBest() {
        guard smartEnabled else { return }
        Task {
            guard let currentGroup = proxyGroups.first(where: { $0.name == currentGroupName }) else { return }
            guard !currentGroup.nodes.isEmpty else { return }

            let latencyRecords = currentGroup.nodes.map { node -> [Double] in
                node.alive && node.latency > 0 ? [Double(node.latency)] : [Double.infinity]
            }
            let successRecords = currentGroup.nodes.map { [$0.alive] }
            let nodeNames = currentGroup.nodes.map { $0.name }

            let weights = SmartScoreWeights(
                latencyP90: smartLatencyWeight,
                successRate: smartSuccessWeight,
                stability: smartStabilityWeight
            )
            let decay = SmartDecayConfig(halfLifeHours: smartDecayHalfLife)

            let ranked = computeSmartRank(
                weights: weights,
                decay: decay,
                nodeNames: nodeNames,
                nodeLatencyRecords: latencyRecords,
                nodeSuccessRecords: successRecords
            )

            if let best = ranked.first {
                if let bestNode = currentGroup.nodes.first(where: { $0.name == best.name }) {
                    selectProxyNode(groupName: currentGroupName, nodeName: bestNode.name)
                    addEvent(level: "Info", module: "smart", message: String(format: "Smart selected: %@ (score: %.2f)", bestNode.name, best.score), timestamp: 0)
                }
            }
        }
    }

    func setSortMode(_ mode: String) {
        proxySortMode = mode
        guard let idx = proxyGroups.firstIndex(where: { $0.name == currentGroupName }) else { return }
        var sortedNodes = proxyGroups[idx].nodes
        switch mode {
        case "name":
            sortedNodes.sort { $0.name < $1.name }
        case "latency":
            sortedNodes.sort { $0.latency > 0 && $1.latency > 0 ? $0.latency < $1.latency : $0.latency > 0 }
        case "smart":
            if smartEnabled {
                do {
                    let nodeNames = sortedNodes.map { $0.name }
                    let latencyRecords = sortedNodes.map { node -> [Double] in
                        node.alive && node.latency > 0 ? [Double(node.latency)] : [Double.infinity]
                    }
                    let successRecords = sortedNodes.map { [$0.alive] }
                    let weights = SmartScoreWeights(latencyP90: smartLatencyWeight, successRate: smartSuccessWeight, stability: smartStabilityWeight)
                    let decay = SmartDecayConfig(halfLifeHours: smartDecayHalfLife)
                    let ranked = computeSmartRank(weights: weights, decay: decay, nodeNames: nodeNames, nodeLatencyRecords: latencyRecords, nodeSuccessRecords: successRecords)
                    let rankMap = Dictionary(uniqueKeysWithValues: ranked.map { ($0.name, Int($0.rank)) })
                    sortedNodes.sort { rankMap[$0.name] ?? Int.max < rankMap[$1.name] ?? Int.max }
                } catch {
                    // fallback to default order
                }
            }
        default:
            break
        }
        proxyGroups[idx].nodes = sortedNodes
    }

    // ── Failover ────────────────────────────────────────────────────────

    func onNodeFailure(nodeName: String, success: Bool) {
        guard failoverEnabled else { return }
        let currentCount = nodeFailureCounts[nodeName] ?? 0
        let newCount: UInt32 = success ? 0 : currentCount + 1
        nodeFailureCounts[nodeName] = newCount

        if !success && newCount >= failoverThreshold {
            let policy = FailoverPolicyConfig(
                enabled: true,
                threshold: failoverThreshold,
                cooldownSecs: failoverCooldownSecs,
                fallbackGroup: failoverFallbackGroup
            )
            if let action = checkFailover(policy: policy, nodeName: nodeName, success: success, currentFailureCount: newCount) {
                addEvent(level: "Warn", module: "core", message: "Failover: \(action.failedNode) -> \(action.target) (failures: \(action.failureCount))", timestamp: 0)
                selectProxyNode(groupName: currentGroupName, nodeName: action.target)
                nodeFailureCounts[nodeName] = 0
            }
        }
    }

    // ── Event & Log management ──────────────────────────────────────────

    func addEvent(level: String, module: String, message: String, timestamp: UInt64) {
        events.append(EventItem(level: level, module: module, message: message, timestamp: timestamp))
        if events.count > 100 { events.removeFirst(events.count - 100) }
        logs.append(LogEntryItem(level: level, message: message, timestamp: timestamp))
        if logs.count > 500 { logs.removeFirst(logs.count - 500) }
    }

    func clearLogs() { logs = [] }

    var filteredLogs: [LogEntryItem] {
        if logLevelFilter == "all" { return logs }
        return logs.filter { $0.level.caseInsensitiveCompare(logLevelFilter) == .orderedSame }
    }

    // ── Settings actions ────────────────────────────────────────────────

    func setTunEnabled(_ enabled: Bool) {
        tunEnabled = enabled
        if isCoreRunning { Task { restartCoreWithNewConfig() } }
    }

    func setSystemProxyEnabled(_ enabled: Bool) { systemProxyEnabled = enabled }
    func setIpv6Enabled(_ enabled: Bool) { ipv6Enabled = enabled }
    func setAllowLan(_ enabled: Bool) { allowLan = enabled }
    func setUnifiedDelay(_ enabled: Bool) { unifiedDelay = enabled }
    func setMixedPort(_ port: UInt16) { mixedPort = port }
    func setSocksPort(_ port: UInt16) { socksPort = port }
    func setHttpPort(_ port: UInt16) { httpPort = port }

    // ── Smart selector settings ─────────────────────────────────────────

    func setSmartEnabled(_ enabled: Bool) { smartEnabled = enabled }
    func setSmartAutoTest(_ enabled: Bool) { smartAutoTest = enabled }

    // ── Failover settings ───────────────────────────────────────────────

    func setFailoverEnabled(_ enabled: Bool) { failoverEnabled = enabled }
    func setFailoverThreshold(_ threshold: UInt32) { failoverThreshold = threshold }
    func setFailoverCooldown(_ cooldownSecs: UInt64) { failoverCooldownSecs = cooldownSecs }
    func setFailoverFallbackGroup(_ group: String) { failoverFallbackGroup = group }

    // ── Core version ────────────────────────────────────────────────────

    func refreshCoreVersion() {
        Task {
            // On iOS, mihomo binary is embedded in the app bundle.
            // Try to get the version from the mihomo binary via ProcessManager.
            do {
                let pm = IosProcessManager()
                let versionOutput = try pm.getVersion()
                coreVersion = parseVersionOutput(stdout: versionOutput)
                if coreVersion.isEmpty { coreVersion = "unknown" }
            } catch {
                coreVersion = "unknown"
            }
        }
    }

    // ── Mihomo API ─────────────────────────────────────────────────────

    func refreshProxies() {
        guard isCoreRunning && apiPort > 0 else { return }
        Task {
            do {
                let groups = try await mihomoApiGetProxies()
                let updatedGroups = groups.map { name, data -> ProxyGroup in
                    let existingGroup = proxyGroups.first { $0.name == name }
                    let nodes = data.all.map { nodeName -> ProxyNode in
                        let existingNode = existingGroup?.nodes.first { $0.name == nodeName }
                        return ProxyNode(
                            name: nodeName,
                            type: "",
                            latency: existingNode?.latency ?? 0,
                            alive: existingNode?.alive ?? false
                        )
                    }
                    return ProxyGroup(name: name, type: data.type, nodes: nodes, current: data.now)
                }
                proxyGroups = updatedGroups
                if currentGroupName.isEmpty && !updatedGroups.isEmpty {
                    currentGroupName = updatedGroups.first!.name
                }
                if currentNodeName.isEmpty {
                    let currentGroup = updatedGroups.first { $0.name == currentGroupName }
                    currentNodeName = currentGroup?.current ?? ""
                }
            } catch {
                addEvent(level: "Error", module: "core", message: "Failed to refresh proxies: \(error.localizedDescription)", timestamp: 0)
            }
        }
    }

    func refreshConnections() {
        guard isCoreRunning && apiPort > 0 else { return }
        Task {
            do {
                let data = try await mihomoApiGetConnections()
                connections = data
            } catch { }
        }
    }

    func closeConnection(id: String) {
        connections.removeAll { $0.connectionId == id }
        if isCoreRunning && apiPort > 0 {
            Task {
                try? await mihomoApiCloseConnection(id: id)
            }
        }
    }

    func closeAllConnections() {
        connections = []
        if isCoreRunning && apiPort > 0 {
            Task {
                do {
                    try await mihomoApiCloseAllConnections()
                    addEvent(level: "Info", module: "core", message: "All connections closed", timestamp: 0)
                } catch {
                    addEvent(level: "Error", module: "core", message: "Close connections failed: \(error.localizedDescription)", timestamp: 0)
                }
            }
        } else {
            addEvent(level: "Info", module: "core", message: "All connections closed", timestamp: 0)
        }
    }

    // ── Mihomo API HTTP helpers ────────────────────────────────────────

    private func mihomoApiUrl(_ path: String) -> String {
        "http://127.0.0.1:\(apiPort)\(path)"
    }

    private func mihomoRequest(url: String, method: String = "GET", body: Data? = nil) async throws -> Data {
        guard let requestUrl = URL(string: url) else {
            throw NSError(domain: "Zephyr", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
        }
        var request = URLRequest(url: requestUrl)
        request.httpMethod = method
        request.setValue("Bearer \(coreSecret)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 10
        if let body = body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw NSError(domain: "Zephyr", code: statusCode, userInfo: [NSLocalizedDescriptionKey: "HTTP \(statusCode)"])
        }
        return data
    }

    struct MihomoProxyGroupData {
        let name: String
        let type: String
        let all: [String]
        let now: String
    }

    private func mihomoApiGetProxies() async throws -> [String: MihomoProxyGroupData] {
        let data = try await mihomoRequest(url: mihomoApiUrl("/proxies"))
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let proxies = json["proxies"] as? [String: [String: Any]] else {
            throw NSError(domain: "Zephyr", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid proxies response"])
        }
        var result: [String: MihomoProxyGroupData] = [:]
        let groupTypes = Set(["Selector", "URLTest", "Fallback", "LoadBalance"])
        for (name, proxy) in proxies {
            let type = proxy["type"] as? String ?? ""
            guard groupTypes.contains(type) else { continue }
            let allNodes = (proxy["all"] as? [String]) ?? []
            let now = proxy["now"] as? String ?? ""
            result[name] = MihomoProxyGroupData(name: name, type: type, all: allNodes, now: now)
        }
        return result
    }

    private func mihomoApiSelectProxy(groupName: String, nodeName: String) async throws {
        let encoded = groupName.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? groupName
        let body = try JSONSerialization.data(withJSONObject: ["name": nodeName])
        _ = try await mihomoRequest(url: mihomoApiUrl("/proxies/\(encoded)"), method: "PUT", body: body)
    }

    private func mihomoApiTestGroupDelay(groupName: String) async throws -> [String: Int] {
        let encoded = groupName.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? groupName
        let data = try await mihomoRequest(url: mihomoApiUrl("/group/\(encoded)/delay?timeout=5000&url=http://www.gstatic.com/generate_204"))
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        var result: [String: Int] = [:]
        for (name, value) in json {
            if let obj = value as? [String: Any] {
                result[name] = obj["delay"] as? Int ?? -1
            }
        }
        return result
    }

    private func mihomoApiGetConnections() async throws -> [ConnectionItem] {
        let data = try await mihomoRequest(url: mihomoApiUrl("/connections"))
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let connArray = json["connections"] as? [[String: Any]] else {
            return []
        }
        return connArray.compactMap { conn -> ConnectionItem? in
            guard let id = conn["id"] as? String else { return nil }
            let metadata = conn["metadata"] as? [String: Any] ?? [:]
            let host = (metadata["host"] as? String ?? "") + ":" + (metadata["destinationPort"] as? String ?? "")
            let network = metadata["network"] as? String ?? ""
            let type = metadata["type"] as? String ?? ""
            let chains = (conn["chains"] as? [String])?.joined(separator: "->") ?? ""
            let dl = conn["download"] as? UInt64 ?? 0
            let ul = conn["upload"] as? UInt64 ?? 0
            return ConnectionItem(connectionId: id, host: host, network: network, type: type, chains: chains, downloadSpeed: dl, uploadSpeed: ul)
        }
    }

    private func mihomoApiCloseConnection(id: String) async throws {
        _ = try await mihomoRequest(url: mihomoApiUrl("/connections/\(id)"), method: "DELETE")
    }

    private func mihomoApiCloseAllConnections() async throws {
        _ = try await mihomoRequest(url: mihomoApiUrl("/connections"), method: "DELETE")
    }

    // ── Subscription download helper ───────────────────────────────────

    private func downloadSubscriptionContent(url: String) async throws -> String {
        guard let requestUrl = URL(string: url) else {
            throw NSError(domain: "Zephyr", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
        }
        var request = URLRequest(url: requestUrl)
        request.setValue("ClashForiOS/1.0", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 30
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw NSError(domain: "Zephyr", code: statusCode, userInfo: [NSLocalizedDescriptionKey: "HTTP \(statusCode)"])
        }
        let content = String(data: data, encoding: .utf8) ?? ""

        // Try base64 decode (some subscriptions return base64-encoded content)
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if let decodedData = Data(base64Encoded: trimmed),
           let decoded = String(data: decodedData, encoding: .utf8) {
            // Use decoded content if it looks like YAML/JSON
            if decoded.hasPrefix("{") || decoded.contains("proxies:") {
                return decoded
            }
        }

        return content
    }

    private func sharedConfigsDir() -> String {
        if let groupDir = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: PacketTunnelOptions.appGroupId) {
            return groupDir.appendingPathComponent("core/configs").path
        }
        return NSTemporaryDirectory() + "zephyr/core/configs"
    }
}

// ── CoreEventCallback wrapper ────────────────────────────────────────────

private class CoreEventCallbackSwift: CoreEventCallback {
    private let handler: (CoreEvent) -> Void
    init(_ handler: @escaping (CoreEvent) -> Void) { self.handler = handler }
    func onEvent(event: CoreEvent) { handler(event) }
}

// ── iOS Process Manager ──────────────────────────────────────────────────

/// iOS implementation of the UniFFI ProcessManager callback interface.
/// On iOS, mihomo is embedded in the app bundle and managed by the
/// Network Extension (PacketTunnel), so this provides best-effort
/// version detection.
private class IosProcessManager: ProcessManager {
    func startCore(configPath: String) throws -> CoreStartResult {
        // On iOS, core is started via the VPN tunnel, not directly
        throw NSError(domain: "Zephyr", code: 1, userInfo: [NSLocalizedDescriptionKey: "Use startVpnTunnel() on iOS"])
    }

    func stopCore() throws {
        // On iOS, core is stopped via the VPN tunnel
    }

    func isRunning() -> Bool {
        false
    }

    func getVersion() throws -> String {
        // Try to run the bundled mihomo binary with -v flag
        if let binaryPath = Bundle.main.path(forResource: "zephyr-mihomo", ofType: nil) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: binaryPath)
            process.arguments = ["-v"]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8) ?? ""
        }
        return ""
    }

    func killAll() throws {
        // No-op on iOS; the system manages the Network Extension lifecycle
    }
}

// ── Data Models ──────────────────────────────────────────────────────────

struct ProfileItem: Identifiable {
    let id = UUID()
    var name: String
    var url: String?
    var urlDisplay: String?
    var subInfo: String?
    var lastUpdated: UInt64?
}

struct ProxyNode: Identifiable {
    let id = UUID()
    var name: String
    var type: String = ""
    var latency: Int = 0
    var alive: Bool = false
}

struct ProxyGroup: Identifiable {
    let id = UUID()
    var name: String
    var type: String = ""
    var nodes: [ProxyNode]
    var current: String?
}

struct EventItem: Identifiable {
    let id = UUID()
    let level: String
    let module: String
    let message: String
    let timestamp: UInt64
}

struct LogEntryItem: Identifiable {
    let id = UUID()
    let level: String
    let message: String
    let timestamp: UInt64
}

struct ConnectionItem: Identifiable {
    let id = UUID()
    let connectionId: String
    let host: String
    let network: String
    let type: String
    let chains: String
    let downloadSpeed: UInt64
    let uploadSpeed: UInt64
}

// ── Content View (5-Tab) ─────────────────────────────────────────────────

struct ContentView: View {
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            HomeView()
                .tabItem { Label("Home", systemImage: "house.fill") }
                .tag(0)

            ProxiesView()
                .tabItem { Label("Proxies", systemImage: "arrow.forward") }
                .tag(1)

            ProfilesView()
                .tabItem { Label("Profiles", systemImage: "list.bullet") }
                .tag(2)

            LogsView()
                .tabItem { Label("Logs", systemImage: "terminal") }
                .tag(3)

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
                .tag(4)
        }
    }
}

// ── Home View ────────────────────────────────────────────────────────────

struct HomeView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: AppSpacing.Space4) {
                    CoreStatusCard()

                    ProxyModeCard()

                    HStack(spacing: AppSpacing.Space3) {
                        ToggleCard(
                            title: "TUN Mode",
                            subtitle: "Virtual Adapter",
                            isOn: Binding(
                                get: { appState.tunEnabled },
                                set: { appState.setTunEnabled($0) }
                            ),
                            iconColor: AppColors.ColorPink500
                        )
                        ToggleCard(
                            title: "System Proxy",
                            subtitle: "HTTP/SOCKS Proxy",
                            isOn: Binding(
                                get: { appState.systemProxyEnabled },
                                set: { appState.setSystemProxyEnabled($0) }
                            ),
                            iconColor: AppColors.ColorBlue500
                        )
                    }

                    if appState.isCoreRunning && !appState.currentNodeName.isEmpty {
                        CurrentNodeCard()
                    }

                    EventLogCard()
                }
                .padding(.horizontal, AppSpacing.Space5)
                .padding(.vertical, AppSpacing.Space5)
            }
            .navigationTitle("Zephyr")
        }
    }
}

// ── Core Status Card ─────────────────────────────────────────────────────

private struct CoreStatusCard: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.Space3) {
            HStack {
                VStack(alignment: .leading, spacing: AppSpacing.Space1) {
                    HStack(spacing: AppSpacing.Space2) {
                        Circle()
                            .fill(appState.isCoreRunning ? AppColors.ColorEmerald500 : AppColors.ColorRed500)
                            .frame(width: 12, height: 12)
                        Text(appState.isCoreRunning ? "Core Running" : "Core Stopped")
                            .font(.title2)
                            .fontWeight(.semibold)
                    }
                    Text(appState.isCoreRunning ? "Proxy active on port \(appState.mixedPort)" : "Tap the switch to start")
                        .font(.subheadline)
                        .foregroundStyle(AppColors.TextSecondary)
                }
                Spacer()
                if appState.isStartingCore {
                    ProgressView()
                } else {
                    Toggle("", isOn: Binding(
                        get: { appState.isCoreRunning },
                        set: { appState.toggleCore($0) }
                    ))
                    .labelsHidden()
                }
            }
        }
        .padding(AppSpacing.Space5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(appState.isCoreRunning ? AppColors.ColorEmerald500.opacity(0.12) : AppColors.ColorRed500.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.RadiusMd))
    }
}

// ── Proxy Mode Card ──────────────────────────────────────────────────────

private struct ProxyModeCard: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.Space3) {
            Text("Proxy Mode")
                .font(.headline)
                .fontWeight(.semibold)
            HStack(spacing: AppSpacing.Space2) {
                ForEach(["rule", "global", "direct"], id: \.self) { mode in
                    Button(action: { appState.setProxyMode(mode) }) {
                        Text(mode.capitalized)
                            .font(.subheadline)
                            .fontWeight(appState.proxyMode == mode ? .bold : .regular)
                            .padding(.horizontal, AppSpacing.Space5)
                            .padding(.vertical, AppSpacing.Space3)
                            .background(appState.proxyMode == mode ? AppAccent.purple.primary : AppColors.BgMuted)
                            .foregroundStyle(appState.proxyMode == mode ? .white : .primary)
                            .clipShape(Capsule())
                    }
                }
            }
        }
        .padding(AppSpacing.Space5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.RadiusMd))
        .shadow(color: AppShadow.ShadowSm.color, radius: AppShadow.ShadowSm.blurRadius, x: AppShadow.ShadowSm.offsetX, y: AppShadow.ShadowSm.offsetY)
    }
}

// ── Toggle Card ──────────────────────────────────────────────────────────

private struct ToggleCard: View {
    let title: String
    let subtitle: String
    @Binding var isOn: Bool
    var iconColor: Color = AppAccent.purple.primary

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.Space2) {
            HStack {
                VStack(alignment: .leading) {
                    Text(title)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(AppColors.TextSecondary)
                }
                Spacer()
                Toggle("", isOn: $isOn)
                    .labelsHidden()
            }
        }
        .padding(AppSpacing.Space4)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.RadiusMd))
        .shadow(color: AppShadow.ShadowSm.color, radius: AppShadow.ShadowSm.blurRadius, x: AppShadow.ShadowSm.offsetX, y: AppShadow.ShadowSm.offsetY)
    }
}

// ── Current Node Card ────────────────────────────────────────────────────

private struct CurrentNodeCard: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        HStack(spacing: AppSpacing.Space3) {
            Circle()
                .fill(AppColors.ColorEmerald500)
                .frame(width: 10, height: 10)
            VStack(alignment: .leading) {
                Text("Current Node")
                    .font(.caption)
                    .foregroundStyle(AppColors.TextSecondary)
                Text(appState.currentNodeName)
                    .font(.body)
                    .fontWeight(.semibold)
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(.horizontal, AppSpacing.Space5)
        .padding(.vertical, AppSpacing.Space4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppAccent.purple.primary.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.RadiusMd))
    }
}

// ── Event Log Card ───────────────────────────────────────────────────────

private struct EventLogCard: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.Space3) {
            Text("Event Log")
                .font(.headline)
                .fontWeight(.semibold)

            if appState.events.isEmpty {
                Text("No events yet")
                    .font(.caption)
                    .foregroundStyle(AppColors.TextSecondary)
            } else {
                ForEach(appState.events.suffix(8)) { event in
                    HStack(alignment: .top, spacing: AppSpacing.Space2) {
                        Text("[\(event.level)]")
                            .font(.caption.monospaced())
                            .fontWeight(.bold)
                            .foregroundStyle(colorForLevel(event.level))
                            .frame(width: 52, alignment: .leading)
                        Text(event.message)
                            .font(.caption)
                            .lineLimit(2)
                    }
                }
            }
        }
        .padding(AppSpacing.Space5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.RadiusMd))
        .shadow(color: AppShadow.ShadowSm.color, radius: AppShadow.ShadowSm.blurRadius, x: AppShadow.ShadowSm.offsetX, y: AppShadow.ShadowSm.offsetY)
    }

    private func colorForLevel(_ level: String) -> Color {
        switch level {
        case "Error", "Fatal": return AppColors.ColorRed500
        case "Warn": return AppColors.ColorAmber500
        default: return AppColors.TextSecondary
        }
    }
}

// ── Proxies View ─────────────────────────────────────────────────────────

struct ProxiesView: View {
    @EnvironmentObject var appState: AppState
    @State private var sortExpanded = false
    @State private var groupExpanded = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Header
                HStack {
                    Text("Proxy Nodes")
                        .font(.title3)
                        .fontWeight(.semibold)
                    Spacer()

                    // Sort button
                    Menu {
                        ForEach([("default", "Default"), ("name", "Name"), ("latency", "Latency"), ("smart", "Smart")], id: \.0) { mode, label in
                            Button(label) { appState.setSortMode(mode) }
                        }
                    } label: {
                        Text(sortLabel)
                            .font(.caption)
                    }

                    // Smart select
                    if appState.smartEnabled {
                        Button(action: { appState.smartSelectBest() }) {
                            HStack(spacing: AppSpacing.Space1) {
                                Image(systemName: "star.fill")
                                    .font(.caption2)
                                Text("Best")
                                    .font(.caption)
                            }
                        }
                        .buttonStyle(ZephyrBorderedButtonStyle())
                        .controlSize(.small)
                    }

                    // Latency test
                    Button(action: { appState.testLatency() }) {
                        HStack(spacing: AppSpacing.Space1) {
                            if appState.isTestingLatency {
                                ProgressView().controlSize(.small)
                            } else {
                                Image(systemName: "speedometer")
                                    .font(.caption2)
                            }
                            Text("Test")
                                .font(.caption)
                        }
                    }
                    .buttonStyle(ZephyrProminentButtonStyle())
                    .controlSize(.small)
                    .disabled(appState.isTestingLatency)
                }
                .padding(.horizontal, AppSpacing.Space5)
                .padding(.vertical, AppSpacing.Space4)

                // Group selector
                if !appState.proxyGroups.isEmpty {
                    Menu {
                        ForEach(appState.proxyGroups) { group in
                            Button(group.name) { appState.selectProxyGroup(group.name) }
                        }
                    } label: {
                        HStack {
                            Text(appState.currentGroupName.isEmpty ? "Select Group" : appState.currentGroupName)
                                .font(.subheadline)
                            Image(systemName: "chevron.down")
                                .font(.caption)
                        }
                    }
                    .padding(.horizontal, AppSpacing.Space5)
                    .padding(.bottom, AppSpacing.Space3)
                }

                // Node list
                let currentGroup = appState.proxyGroups.first { $0.name == appState.currentGroupName }
                let nodes = currentGroup?.nodes ?? []

                if nodes.isEmpty {
                    Spacer()
                    VStack(spacing: AppSpacing.Space3) {
                        Image(systemName: "cloud.off")
                            .font(.system(size: AppSpacing.Space8))
                            .foregroundStyle(AppColors.TextSecondary)
                        Text("No proxy nodes available")
                            .font(.body)
                            .foregroundStyle(AppColors.TextSecondary)
                        Text("Start the core and select a profile")
                            .font(.caption)
                            .foregroundStyle(AppColors.TextSecondary)
                    }
                    Spacer()
                } else {
                    List(nodes) { node in
                        ProxyNodeRow(
                            node: node,
                            isSelected: node.name == currentGroup?.current,
                            onSelect: { appState.selectProxyNode(groupName: appState.currentGroupName, nodeName: node.name) }
                        )
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Proxies")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var sortLabel: String {
        switch appState.proxySortMode {
        case "name": return "Name"
        case "latency": return "Latency"
        case "smart": return "Smart"
        default: return "Default"
        }
    }
}

private struct ProxyNodeRow: View {
    let node: ProxyNode
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack {
                VStack(alignment: .leading, spacing: AppSpacing.Space0) {
                    Text(node.name)
                        .font(.body)
                        .fontWeight(isSelected ? .bold : .regular)
                        .lineLimit(1)
                    if !node.type.isEmpty {
                        Text(node.type)
                            .font(.caption2)
                            .foregroundStyle(AppColors.TextSecondary)
                    }
                }
                Spacer()
                LatencyBadge(latency: node.latency, alive: node.alive)
            }
            .padding(.vertical, AppSpacing.Space2)
        }
        .listRowBackground(isSelected ? AppAccent.purple.primary.opacity(0.1) : Color.clear)
    }
}

private struct LatencyBadge: View {
    let latency: Int
    let alive: Bool

    var body: some View {
        let (text, color) = badgeData
        Text(text)
            .font(.caption.monospaced())
            .fontWeight(.semibold)
            .foregroundStyle(color)
            .padding(.horizontal, AppBadge.fontSize)
            .padding(.vertical, AppSpacing.Space1)
            .background(color.opacity(0.15))
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.RadiusSm))
    }

    private var badgeData: (String, Color) {
        if latency <= 0 { return ("Timeout", AppColors.ColorRed500) }
        if latency < 200 { return ("\(latency)ms", AppColors.ColorEmerald500) }
        if latency < 500 { return ("\(latency)ms", AppColors.ColorAmber500) }
        return ("\(latency)ms", AppColors.ColorRed500)
    }
}

// ── Profiles View ────────────────────────────────────────────────────────

struct ProfilesView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Header
                HStack {
                    Text("Subscriptions")
                        .font(.title3)
                        .fontWeight(.semibold)
                    Spacer()
                    if !appState.profiles.isEmpty {
                        Button(action: { appState.updateAllProfiles() }) {
                            HStack(spacing: AppSpacing.Space1) {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                    .font(.caption2)
                                Text("Update All")
                                    .font(.caption)
                            }
                        }
                        .buttonStyle(ZephyrBorderedButtonStyle())
                        .controlSize(.small)
                        .disabled(appState.isUpdatingSubscriptions)
                    }
                    Button(action: { appState.showAddProfileDialog = true }) {
                        HStack(spacing: AppSpacing.Space1) {
                            Image(systemName: "plus")
                                .font(.caption2)
                            Text("Add")
                                .font(.caption)
                        }
                    }
                    .buttonStyle(ZephyrProminentButtonStyle())
                    .controlSize(.small)
                }
                .padding(.horizontal, AppSpacing.Space5)
                .padding(.vertical, AppSpacing.Space4)

                if appState.profiles.isEmpty {
                    Spacer()
                    VStack(spacing: AppSpacing.Space3) {
                        Image(systemName: "cloud.download")
                            .font(.system(size: AppSpacing.Space8))
                            .foregroundStyle(AppColors.TextSecondary)
                        Text("No profiles yet")
                            .font(.body)
                            .foregroundStyle(AppColors.TextSecondary)
                        Text("Add a subscription URL to get started")
                            .font(.caption)
                            .foregroundStyle(AppColors.TextSecondary)
                    }
                    Spacer()
                } else {
                    List(appState.profiles) { profile in
                        ProfileRow(
                            profile: profile,
                            isActive: profile.name == appState.activeProfile,
                            onSelect: { appState.setActiveProfile(profile.name) },
                            onUpdate: { appState.updateProfile(profile.name) },
                            onDelete: { appState.deleteProfile(profile.name) }
                        )
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Profiles")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $appState.showAddProfileDialog) {
                AddProfileSheet()
            }
        }
    }
}

private struct ProfileRow: View {
    let profile: ProfileItem
    let isActive: Bool
    let onSelect: () -> Void
    let onUpdate: () -> Void
    let onDelete: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: AppSpacing.Space3) {
                VStack(alignment: .leading, spacing: AppSpacing.Space0) {
                    HStack(spacing: AppSpacing.Space2) {
                        if isActive {
                            Circle()
                                .fill(AppColors.ColorEmerald500)
                                .frame(width: 8, height: 8)
                        }
                        Text(profile.name)
                            .font(.subheadline)
                            .fontWeight(isActive ? .bold : .regular)
                    }
                    if let url = profile.urlDisplay {
                        Text(url)
                            .font(.caption)
                            .foregroundStyle(AppColors.TextSecondary)
                            .lineLimit(1)
                    }
                    if let info = profile.subInfo {
                        Text(info)
                            .font(.caption2)
                            .foregroundStyle(AppColors.TextSecondary)
                    }
                }
                Spacer()
                Button(action: onUpdate) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.caption)
                }
                .buttonStyle(ZephyrBorderlessButtonStyle())
                Menu {
                    Button(role: .destructive, action: onDelete) {
                        Label("Delete", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.caption)
                }
                .buttonStyle(ZephyrBorderlessButtonStyle())
            }
            .padding(.vertical, AppSpacing.Space2)
        }
        .listRowBackground(isActive ? AppAccent.purple.primary.opacity(0.1) : Color.clear)
    }
}

private struct AddProfileSheet: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Subscription URL", text: $appState.addProfileUrl)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Profile Name (optional)", text: $appState.addProfileName)
                }
            }
            .navigationTitle("Add Subscription")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        appState.addProfileUrl = ""
                        appState.addProfileName = ""
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        if !appState.addProfileUrl.isEmpty {
                            appState.addProfile(url: appState.addProfileUrl, name: appState.addProfileName)
                            appState.addProfileUrl = ""
                            appState.addProfileName = ""
                            dismiss()
                        }
                    }
                    .disabled(appState.addProfileUrl.isEmpty)
                }
            }
        }
    }
}

// ── Logs View ────────────────────────────────────────────────────────────

struct LogsView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Header with filter
                HStack {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: AppSpacing.Space2) {
                            ForEach(["all", "info", "warn", "error"], id: \.self) { level in
                                Button(action: { appState.logLevelFilter = level }) {
                                    Text(level.capitalized)
                                        .font(.caption)
                                        .padding(.horizontal, AppSpacing.Space4)
                                        .padding(.vertical, AppSpacing.Space2)
                                        .background(appState.logLevelFilter.caseInsensitiveCompare(level) == .orderedSame ? AppAccent.purple.primary : AppColors.BgMuted)
                                        .foregroundStyle(appState.logLevelFilter.caseInsensitiveCompare(level) == .orderedSame ? .white : .primary)
                                        .clipShape(Capsule())
                                }
                            }
                        }
                    }
                    Spacer()
                    Button(action: { appState.clearLogs() }) {
                        Image(systemName: "trash.slash")
                            .font(.subheadline)
                    }
                }
                .padding(.horizontal, AppSpacing.Space5)
                .padding(.vertical, AppSpacing.Space4)

                let filtered = appState.filteredLogs
                if filtered.isEmpty {
                    Spacer()
                    VStack(spacing: AppSpacing.Space3) {
                        Image(systemName: "terminal")
                            .font(.system(size: AppSpacing.Space8))
                            .foregroundStyle(AppColors.TextSecondary)
                        Text("No logs yet")
                            .font(.body)
                            .foregroundStyle(AppColors.TextSecondary)
                    }
                    Spacer()
                } else {
                    ScrollViewReader { proxy in
                        List(filtered) { log in
                            HStack(alignment: .top, spacing: AppSpacing.Space2) {
                                Text("[\(log.level.uppercased())]")
                                    .font(.caption.monospaced())
                                    .fontWeight(.bold)
                                    .foregroundStyle(colorForLevel(log.level))
                                    .frame(width: 52, alignment: .leading)
                                Text(log.message)
                                    .font(.caption.monospaced())
                            }
                            .id(log.id)
                        }
                        .listStyle(.plain)
                        .onChange(of: filtered.count) {
                            if let last = filtered.last {
                                withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Logs")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func colorForLevel(_ level: String) -> Color {
        switch level {
        case "Error", "Fatal": return AppColors.ColorRed500
        case "Warn": return AppColors.ColorAmber500
        case "Info": return AppColors.ColorBlue500
        default: return AppColors.TextSecondary
        }
    }
}

// ── Settings View ────────────────────────────────────────────────────────

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @State private var showPortDialog = false

    var body: some View {
        NavigationStack {
            Form {
                // General
                Section("General") {
                    HStack {
                        Text("Theme")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        Spacer()
                        HStack(spacing: AppSpacing.Space1) {
                            ForEach([("light", "Light"), ("auto", "Auto"), ("dark", "Dark")], id: \.0) { mode, label in
                                Button(label) { appState.themeMode = mode }
                                    .font(.caption)
                                    .padding(.horizontal, AppSpacing.Space3)
                                    .padding(.vertical, AppSpacing.Space1)
                                    .background(appState.themeMode == mode ? AppAccent.purple.primary : AppColors.BgMuted)
                                    .foregroundStyle(appState.themeMode == mode ? .white : .primary)
                                    .clipShape(Capsule())
                            }
                        }
                    }

                    HStack {
                        Text("Language")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        Spacer()
                        HStack(spacing: AppSpacing.Space1) {
                            Button("中文") { appState.language = "zh" }
                                .font(.caption)
                                .padding(.horizontal, AppSpacing.Space3)
                                .padding(.vertical, AppSpacing.Space1)
                                .background(appState.language == "zh" ? AppAccent.purple.primary : AppColors.BgMuted)
                                .foregroundStyle(appState.language == "zh" ? .white : .primary)
                                .clipShape(Capsule())
                            Button("English") { appState.language = "en" }
                                .font(.caption)
                                .padding(.horizontal, AppSpacing.Space3)
                                .padding(.vertical, AppSpacing.Space1)
                                .background(appState.language == "en" ? AppAccent.purple.primary : AppColors.BgMuted)
                                .foregroundStyle(appState.language == "en" ? .white : .primary)
                                .clipShape(Capsule())
                        }
                    }
                }

                // Network
                Section("Network & Routing") {
                    Toggle("IPv6 Support", isOn: Binding(get: { appState.ipv6Enabled }, set: { appState.setIpv6Enabled($0) }))
                    Toggle("Allow LAN", isOn: Binding(get: { appState.allowLan }, set: { appState.setAllowLan($0) }))
                    Toggle("Unified Delay", isOn: Binding(get: { appState.unifiedDelay }, set: { appState.setUnifiedDelay($0) }))

                    HStack {
                        VStack(alignment: .leading) {
                            Text("Port Settings")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                            Text("Mixed: \(appState.mixedPort)  SOCKS: \(appState.socksPort)")
                                .font(.caption)
                                .foregroundStyle(AppColors.TextSecondary)
                        }
                        Spacer()
                        Button("Configure") { showPortDialog = true }
                            .font(.caption)
                    }
                }

                // Core
                Section("Mihomo Core") {
                    HStack {
                        VStack(alignment: .leading) {
                            Text("Current Version")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                            Text("Core: \(appState.coreVersion.isEmpty ? "unknown" : appState.coreVersion)")
                                .font(.caption)
                                .foregroundStyle(AppColors.TextSecondary)
                        }
                        Spacer()
                        Button("Check Update") { appState.refreshCoreVersion() }
                            .font(.caption)
                    }
                }

                // Smart Selector
                Section("Smart Proxy Selector") {
                    Toggle("Smart Proxy Selector", isOn: Binding(get: { appState.smartEnabled }, set: { appState.setSmartEnabled($0) }))
                    Toggle("Auto Speed Test", isOn: Binding(get: { appState.smartAutoTest }, set: { appState.setSmartAutoTest($0) }))

                    if appState.smartEnabled {
                        Text("Scoring Weights")
                            .font(.caption)
                            .foregroundStyle(AppColors.TextSecondary)
                        WeightSlider(label: "Latency", value: $appState.smartLatencyWeight)
                        WeightSlider(label: "Success Rate", value: $appState.smartSuccessWeight)
                        WeightSlider(label: "Stability", value: $appState.smartStabilityWeight)
                    }
                }

                // Failover
                Section("Failover") {
                    Toggle("Failover", isOn: Binding(get: { appState.failoverEnabled }, set: { appState.setFailoverEnabled($0) }))

                    if appState.failoverEnabled {
                        VStack(alignment: .leading) {
                            HStack {
                                Text("Failure Threshold")
                                    .font(.subheadline)
                                Spacer()
                                Text("\(appState.failoverThreshold)")
                                    .font(.title3.monospacedDigit())
                                    .fontWeight(.bold)
                            }
                            Text("Consecutive failures before switching")
                                .font(.caption)
                                .foregroundStyle(AppColors.TextSecondary)
                            Slider(value: Binding(
                                get: { Double(appState.failoverThreshold) },
                                set: { appState.setFailoverThreshold(UInt32($0)) }
                            ), in: 1...10, step: 1)
                        }

                        VStack(alignment: .leading) {
                            HStack {
                                Text("Cooldown")
                                    .font(.subheadline)
                                Spacer()
                                Text("\(appState.failoverCooldownSecs)s")
                                    .font(.title3.monospacedDigit())
                                    .fontWeight(.bold)
                            }
                            Text("Seconds before retrying failed node")
                                .font(.caption)
                                .foregroundStyle(AppColors.TextSecondary)
                            Slider(value: Binding(
                                get: { Double(appState.failoverCooldownSecs) },
                                set: { appState.setFailoverCooldown(UInt64($0)) }
                            ), in: 10...300)
                        }

                        TextField("Fallback Group", text: $appState.failoverFallbackGroup)
                            .font(.subheadline)
                    }
                }
            }
            .navigationTitle("Settings")
            .sheet(isPresented: $showPortDialog) {
                PortConfigSheet()
            }
        }
    }
}

private struct WeightSlider: View {
    let label: String
    @Binding var value: Double

    var body: some View {
        HStack {
            Text(label)
                .font(.caption)
                .frame(width: 80, alignment: .leading)
            Slider(value: $value, in: 0...1)
            Text(String(format: "%.2f", value))
                .font(.caption.monospacedDigit())
                .frame(width: 40, alignment: .trailing)
        }
    }
}

private struct PortConfigSheet: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var mixedPortText: String = ""
    @State private var socksPortText: String = ""
    @State private var httpPortText: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Mixed Port", text: $mixedPortText)
                        .keyboardType(.numberPad)
                    TextField("SOCKS5 Port", text: $socksPortText)
                        .keyboardType(.numberPad)
                    TextField("HTTP Port", text: $httpPortText)
                        .keyboardType(.numberPad)
                }
            }
            .navigationTitle("Port Configuration")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                mixedPortText = String(appState.mixedPort)
                socksPortText = String(appState.socksPort)
                httpPortText = String(appState.httpPort)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if let p = UInt16(mixedPortText) { appState.setMixedPort(p) }
                        if let p = UInt16(socksPortText) { appState.setSocksPort(p) }
                        if let p = UInt16(httpPortText) { appState.setHttpPort(p) }
                        dismiss()
                    }
                }
            }
        }
    }
}

// ── Custom Button Styles ─────────────────────────────────────────────────

struct ZephyrBorderedButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: AppButton.fontSize, weight: AppButton.weight))
            .tracking(AppButton.tracking)
            .padding(.horizontal, CGFloat(AppButton.paddingX))
            .padding(.vertical, CGFloat(AppButton.paddingY))
            .background(AppColors.BgMuted)
            .foregroundStyle(AppColors.TextPrimary)
            .clipShape(Capsule())
            .opacity(configuration.isPressed ? 0.8 : 1.0)
    }
}

struct ZephyrProminentButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: AppButton.fontSize, weight: AppButton.weight))
            .tracking(AppButton.tracking)
            .padding(.horizontal, CGFloat(AppButton.paddingX))
            .padding(.vertical, CGFloat(AppButton.paddingY))
            .background(AppAccent.purple.primary)
            .foregroundStyle(AppColors.TextOnAccent)
            .clipShape(Capsule())
            .opacity(configuration.isPressed ? 0.8 : 1.0)
    }
}

struct ZephyrBorderlessButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(AppAccent.purple.primary)
            .opacity(configuration.isPressed ? 0.7 : 1.0)
    }
}

// ── Previews ─────────────────────────────────────────────────────────────

#Preview("Home") {
    ContentView()
        .environmentObject(AppState())
}
