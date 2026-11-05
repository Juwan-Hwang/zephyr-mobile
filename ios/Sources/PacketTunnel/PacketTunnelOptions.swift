import Foundation

struct PacketTunnelOptions {
    /// Bundle identifier for the PacketTunnel Network Extension target.
    /// Must match the extension's bundle ID in the Xcode project.
    static let tunnelProviderBundleId = "com.zephyr.app.PacketTunnel"

    /// Key used to pass the mihomo config file path from main app to extension.
    static let configPathKey = "configPath"

    /// Key used to pass the mihomo API secret from main app to extension.
    static let secretKey = "secret"

    /// App Group identifier shared between the main app and the Network Extension.
    /// Both targets must have this entitlement for file sharing.
    static let appGroupId = "group.com.zephyr.app"
}
