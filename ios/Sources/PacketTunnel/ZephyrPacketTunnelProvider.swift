import Foundation
import NetworkExtension
import ZephyrCore

class ZephyrPacketTunnelProvider: NEPacketTunnelProvider {

    // MARK: - Properties

    private var mihomoProcess: Process?
    private var configDir: String = ""
    private var configPath: String = ""
    private var coreSecret: String = ""

    // MARK: - NEPacketTunnelProvider Overrides

    override func startTunnel(options: [String: NSObject]? = nil) throws {
        let configPathValue = options?[PacketTunnelOptions.configPathKey] as? String ?? ""
        let secretValue = options?[PacketTunnelOptions.secretKey] as? String ?? ""

        self.configPath = configPathValue
        self.coreSecret = secretValue

        // Resolve config directory from configPath (parent directory)
        if !configPathValue.isEmpty {
            let url = URL(fileURLWithPath: configPathValue)
            self.configDir = url.deletingLastPathComponent().path
        } else {
            // Fallback: use app group shared container
            let fileManager = FileManager.default
            if let groupDir = fileManager.containerURL(forSecurityApplicationGroupIdentifier: "group.com.zephyr.app") {
                self.configDir = groupDir.appendingPathComponent("core").path
                self.configPath = groupDir.appendingPathComponent("core/run_config.yaml").path
            }
        }

        // 1. Build tunnel settings — TUN interface with fake-ip range
        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: "127.0.0.1")

        // IPv4 settings: use 198.18.0.0/16 fake-ip range (matches mihomo default)
        let ipv4Settings = NEIPv4Settings(addresses: ["198.18.0.1"], subnetMasks: ["255.255.0.0"])
        ipv4Settings.includedRoutes = [NEIPv4Route.default()]
        settings.ipv4Settings = ipv4Settings

        // DNS settings: route DNS through the tunnel (mihomo handles DNS resolution)
        let dnsSettings = NEDNSSettings(servers: ["8.8.8.8", "8.8.4.4"])
        dnsSettings.matchDomains = [""] // Match all domains → all DNS goes through tunnel
        settings.dnsSettings = dnsSettings

        // 2. Apply settings, then start mihomo
        self.setTunnelNetworkSettings(settings) { [weak self] error in
            guard let self = self else { return }

            if let error = error {
                self.cancelTunnelWithError(error)
                return
            }

            // 3. Start mihomo process
            self.startMihomo()
        }
    }

    override func stopTunnel(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        stopMihomo()
        completionHandler()
    }

    override func handleAppMessage(_ messageData: Data, completionHandler: ((Data?) -> Void)? = nil) {
        // Handle messages from the main app (e.g., config reload, status query)
        if let message = try? JSONSerialization.jsonObject(with: messageData) as? [String: Any] {
            if message["action"] as? String == "reload" {
                // Restart mihomo with new config
                stopMihomo()
                if let newConfigPath = message["configPath"] as? String {
                    self.configPath = newConfigPath
                }
                startMihomo()
            }
        }
        completionHandler?(nil)
    }

    override func sleep(completionHandler: @escaping () -> Void) {
        // System is going to sleep — mihomo can keep running
        completionHandler()
    }

    override func wake() {
        // System woke up — no special action needed
    }

    // MARK: - Mihomo Process Management

    private func startMihomo() {
        // Locate mihomo binary in the Network Extension bundle
        let exePath = Bundle.main.bundleURL.appendingPathComponent("mihomo")

        guard FileManager.default.fileExists(atPath: exePath.path) else {
            cancelTunnelWithError(
                NSError(domain: "ZephyrPacketTunnel", code: 1,
                        userInfo: [NSLocalizedDescriptionKey: "mihomo binary not found at \(exePath.path)"])
            )
            return
        }

        let process = Process()
        process.executableURL = exePath

        // Match desktop app flags: -d <configDir> -f <configPath>
        var arguments = ["-d", configDir]
        if !configPath.isEmpty {
            arguments += ["-f", configPath]
        }
        process.arguments = arguments

        // Pipe stdout/stderr to /dev/null (mihomo logs to its own file)
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            self.mihomoProcess = process
        } catch {
            cancelTunnelWithError(
                NSError(domain: "ZephyrPacketTunnel", code: 2,
                        userInfo: [NSLocalizedDescriptionKey: "Failed to start mihomo: \(error.localizedDescription)"])
            )
        }
    }

    private func stopMihomo() {
        guard let process = mihomoProcess, process.isRunning else {
            mihomoProcess = nil
            return
        }

        // Send SIGTERM for graceful shutdown (same as desktop)
        process.terminate()
        mihomoProcess = nil
    }
}
