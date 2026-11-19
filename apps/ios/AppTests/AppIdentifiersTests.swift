// 应用标识（Refs #209 D3）：bundle ID / App Group 统一为 com.juwanh.zephyr（上架后不可改）。
// 常量（AppGroup 兜底、Darwin 通知名、小组件 kind）App 与扩展共用 Shared/Core，这里再核对：
// 前缀一致、互不重复；project.yml 与三份 entitlements 的 App Group 和代码兜底值一致，且不再残留旧标识。
// 工程文件用 #filePath 定位读取（同 CoreEngineLiveTests），不依赖测试资源拷贝。

import XCTest

final class AppIdentifiersTests: XCTestCase {
    private static let prefix = "com.juwanh.zephyr"
    private static let legacy = "app.zephyr"

    private var iosRoot: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    }

    private func source(_ path: String) throws -> String {
        try String(contentsOf: iosRoot.appendingPathComponent(path), encoding: .utf8)
    }

    func testAppGroupFallback() {
        XCTAssertEqual(AppGroup.fallbackIdentifier, "group.\(Self.prefix)")
    }

    func testDarwinNotificationNamesSharePrefixAndAreUnique() {
        let names = DarwinNotification.allCases.map(\.rawValue)
        for name in names { XCTAssertTrue(name.hasPrefix(Self.prefix + "."), name) }
        XCTAssertEqual(Set(names).count, names.count)
    }

    func testWidgetKindsSharePrefixAndAreUnique() {
        let kinds = [WidgetKinds.status, WidgetKinds.usage, WidgetKinds.scenes,
                     WidgetKinds.lockScreen, WidgetKinds.connectionControl]
        for kind in kinds { XCTAssertTrue(kind.hasPrefix(Self.prefix + "."), kind) }
        XCTAssertEqual(Set(kinds).count, kinds.count)
    }

    func testProjectBundleIdentifiersAndAppGroup() throws {
        let yml = try source("project.yml")
        XCTAssertFalse(yml.contains(Self.legacy), "project.yml 仍有旧标识 \(Self.legacy)")
        XCTAssertTrue(yml.contains("ZEPHYR_APP_GROUP: \(AppGroup.fallbackIdentifier)"))
        for id in [Self.prefix, "\(Self.prefix).PacketTunnel", "\(Self.prefix).Widgets"] {
            XCTAssertTrue(yml.contains("PRODUCT_BUNDLE_IDENTIFIER: \(id)\n"), id)
        }
    }

    /// CI 先跑 xcodegen generate，它按 project.yml 的 entitlements.properties 重写这三个文件，
    /// 所以这里读到的就是生成后的内容：能力缺失说明 project.yml 的 properties 漏写。
    func testEntitlementsUseSameAppGroup() throws {
        for path in ["App/Zephyr.entitlements", "PacketTunnel/PacketTunnel.entitlements",
                     "Widgets/ZephyrWidgets.entitlements"] {
            let data = try Data(contentsOf: iosRoot.appendingPathComponent(path))
            let plist = try XCTUnwrap(
                PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any], path)
            XCTAssertEqual(plist["com.apple.security.application-groups"] as? [String],
                           [AppGroup.fallbackIdentifier], "\(path): \(plist)")
            XCTAssertEqual(plist["com.apple.developer.networking.networkextension"] as? [String],
                           ["packet-tunnel-provider"], "\(path): \(plist)")
        }
    }

    /// 扩展 bundle ID 必须是 App 的子 ID，NETunnelProviderProtocol 才能找到 provider。
    func testTunnelProviderIdentifierMatchesProject() throws {
        let controller = try source("Shared/Intents/TunnelController.swift")
        XCTAssertTrue(controller.contains("providerBundleIdentifier = \"\(Self.prefix).PacketTunnel\""))
    }
}
