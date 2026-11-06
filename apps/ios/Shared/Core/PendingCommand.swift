// PendingCommand —— 扩展进程无法直接驱动 App 内引擎时的投递通道。
//
// 场景：模拟器 / Debug 下引擎是 App 进程里的 MockEngine，控制中心开关或小组件按钮在扩展进程执行 Intent，
// NE 不可用（模拟器不支持 Packet Tunnel）。扩展把命令写进 App Group 并发 Darwin 通知，
// 正在运行的 App（AppServices）收到后 `take()` 并执行。真机 Release 下由 TunnelController 直接控制 NE，不走这里。

import Foundation

enum PendingCommand: Codable, Sendable, Hashable {
    case setConnected(Bool)
    case setMode(SharedState.Mode)
}

enum PendingCommandChannel {
    private struct Envelope: Codable { var command: PendingCommand; var at: Date }

    static var url: URL { AppGroup.containerURL.appendingPathComponent("pending-command.json") }

    /// 命令过期时间：App 不在运行时，过期命令不应在下次冷启动时“突然生效”。
    static let ttl: TimeInterval = 30

    static func post(_ command: PendingCommand, now: Date = Date()) throws {
        let data = try SharedStore.encoder.encode(Envelope(command: command, at: now))
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        DarwinNotifier.post(.command)
    }

    /// 取出并删除；过期或不存在返回 nil。
    static func take(now: Date = Date()) -> PendingCommand? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        try? FileManager.default.removeItem(at: url)
        guard let env = try? SharedStore.decoder.decode(Envelope.self, from: data),
              now.timeIntervalSince(env.at) <= ttl else { return nil }
        return env.command
    }
}
