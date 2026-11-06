// App Group 容器：App、PacketTunnel、ZephyrWidgets 三个进程共享的目录。
//
// 标识符来自 Info.plist 的 `ZephyrAppGroup`（project.yml 用 $(ZEPHYR_APP_GROUP) 注入），缺失时用常量兜底。
// CI / 模拟器无签名（CODE_SIGNING_ALLOWED=NO）时 entitlements 不生效，`containerURL` 可能为 nil：
// 回退到本进程的 Application Support/ZephyrShared，保证单测与快照在无签名环境下也能读写。

import Foundation

enum AppGroup {
    static let fallbackIdentifier = "group.app.zephyr.mobile"

    static let identifier: String = {
        if let id = Bundle.main.object(forInfoDictionaryKey: "ZephyrAppGroup") as? String,
           !id.isEmpty, !id.hasPrefix("$(") {
            return id
        }
        return fallbackIdentifier
    }()

    /// 共享容器根目录；保证存在。
    static let containerURL: URL = {
        let fm = FileManager.default
        if let url = fm.containerURL(forSecurityApplicationGroupIdentifier: identifier) {
            return url
        }
        let base = (try? fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
            ?? fm.temporaryDirectory
        let url = base.appendingPathComponent("ZephyrShared", isDirectory: true)
        try? fm.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    /// mihomo 工作目录（配置、编译后的规则、缓存）。PacketTunnel 以 mmap 只读方式使用其中的大文件。
    static var coreDirectory: URL {
        let url = containerURL.appendingPathComponent("core", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// mihomo external-controller-unix（扩展监听，App 读策略组/连接）。sun_path 上限 104 字节。
    static var controllerSocketPath: String { containerURL.appendingPathComponent("zm.sock").path }

    /// 是否拿到了真正的 App Group 容器（false = 无签名回退）。
    static var isShared: Bool {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier) != nil
    }
}
