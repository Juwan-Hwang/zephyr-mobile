// App ⇄ PacketTunnel 的 provider message 协议（NETunnelProviderSession.sendProviderMessage / handleAppMessage）。
// JSON 编码，单条消息 < 1 KB。新增请求只追加 case，旧扩展收到未知请求回 `.unsupported`。

import Foundation

enum TunnelRequest: Codable, Sendable, Hashable {
    /// 查询状态 + 累计流量。
    case status
    /// 只查实时速率（App 前台 1 Hz 轮询）。
    case traffic
    /// 切换代理模式（rule/global/direct）。
    case setMode(SharedState.Mode)
    /// 重新加载配置（订阅更新后）。
    case reloadConfig
    /// 批量延迟测试（契约 §5 testLatency）：file = App Group core 目录下的代理定义 JSON（核心 latencyTestBatch 生成，
    /// 可能几十 KB，不走消息体）；结果 JSON 放在 TunnelResponse.payload。
    case urlTest(file: String, url: String, timeoutMs: Int32)
    /// 增量日志（zm_logs）：序号 > since、级别 ≥ minLevel，最多 limit 条；结果 JSON 在 payload。
    case logs(since: Int64, minLevel: String, limit: Int32)
}

struct TunnelResponse: Codable, Sendable, Hashable {
    enum Result: String, Codable, Sendable { case ok, unsupported, failed }

    var result: Result
    var status: SharedState.Status
    var mode: SharedState.Mode
    var since: Date?
    var upBps: Int64
    var downBps: Int64
    var upTotal: Int64
    var downTotal: Int64
    /// 扩展当前常驻内存（字节），用于在设置 → 诊断里观察 NE 50 MB 预算。
    var residentBytes: Int64?
    var errorCode: String?
    /// urlTest 的结果（zm_url_test 原样 JSON）。
    var payload: String?
}

enum TunnelMessageCodec {
    static func encode<T: Encodable>(_ value: T) -> Data? { try? SharedStore.encoder.encode(value) }
    static func decodeRequest(_ data: Data) -> TunnelRequest? { try? SharedStore.decoder.decode(TunnelRequest.self, from: data) }
    static func decodeResponse(_ data: Data) -> TunnelResponse? { try? SharedStore.decoder.decode(TunnelResponse.self, from: data) }
}
