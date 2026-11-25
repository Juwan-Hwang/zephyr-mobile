// TunnelFailureLog —— 扩展启动失败时留给日志页的最后几行（#1 A 真机结论 ③）。
//
// zm_logs 的环形缓冲在扩展进程里；startTunnel 失败后系统很快结束扩展，App 之后经 provider message 什么也读不到，
// 而启动失败前后的那几行正是要看的。扩展在失败时把缓冲尾部（zm_logs JSON）加上失败原因，按同样的
// `{"seq":N,"lines":[{seq,level,msg,at}]}` 格式写进 App Group；App 的日志页（CoreEngine.logs）开头读出来。连上后清掉。
// 文件很小（≤ 61 行），扩展里解码 / 编码一次不影响内存预算。

import Foundation

enum TunnelFailureLog {
    static let fileName = "tunnel-failure-log.json"
    static var url: URL { AppGroup.containerURL.appendingPathComponent(fileName) }

    struct Line: Codable, Equatable, Sendable {
        var seq: Int64
        var level: String
        var msg: String
        var at: Int64
    }

    struct Batch: Codable, Equatable, Sendable {
        var seq: Int64
        var lines: [Line]
    }

    /// 内核日志（zm_logs JSON，可为 nil / 坏的）+ 一行 error 级的失败原因。
    static func make(coreLogsJSON: String?, failure: String, at date: Date) -> Batch {
        var lines = coreLogsJSON.flatMap { try? JSONDecoder().decode(Batch.self, from: Data($0.utf8)) }?.lines ?? []
        let seq = (lines.last?.seq ?? 0) + 1
        lines.append(Line(seq: seq, level: "error", msg: failure, at: Int64(date.timeIntervalSince1970 * 1000)))
        return Batch(seq: seq, lines: lines)
    }

    static func save(coreLogsJSON: String?, failure: String, at date: Date, to url: URL = TunnelFailureLog.url) {
        let batch = make(coreLogsJSON: coreLogsJSON, failure: failure, at: date)
        guard let data = try? JSONEncoder().encode(batch) else { return }
        try? data.write(to: url, options: .atomic)
    }

    /// 原样 JSON（App 用与 zm_logs 相同的解码）；没有为 nil。
    static func load(from url: URL = TunnelFailureLog.url) -> String? {
        guard let data = try? Data(contentsOf: url), !data.isEmpty else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func clear(at url: URL = TunnelFailureLog.url) { try? FileManager.default.removeItem(at: url) }
}
