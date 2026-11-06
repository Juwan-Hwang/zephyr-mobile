// "刚才"列表的一行（原型 08）：把 activeConnections 的连接按域名聚合。
// 契约 §13 的 recentHosts(limit:) 尚未进入 Swift 协议（见 NOTES-H.md），暂由活动连接在客户端聚合。
// 纯 Swift，便于单测（Tests/ZephyrFeaturesTests/RecentHostTests.swift）。

import Foundation
import ZephyrKit

struct RecentHost: Hashable, Identifiable, Sendable {
    var host: String
    /// 场景 id；nil = 直连。
    var scene: String?
    /// 最近一条连接的出口节点名（"DIRECT" 表示直连）。
    var node: String
    var connections: Int
    var totalBytes: Int64
    /// 最近一条连接的开始时间（毫秒）。
    var lastSeenAt: Int64
    /// 该域名下的连接 id（关闭时用）。
    var connectionIds: [String]

    var id: String { host }
    var isDirect: Bool { scene == nil || node == "DIRECT" }

    /// 按域名聚合，最近活跃的在前（同一时刻按流量降序），最多 `limit` 个。
    /// 场景 / 节点取该域名最近的一条连接。
    static func aggregate(_ list: [ConnectionInfo], limit: Int = 50) -> [RecentHost] {
        var byHost: [String: RecentHost] = [:]
        var order: [String] = []
        for c in list {
            let key = c.host.lowercased()
            if var h = byHost[key] {
                h.connections += 1
                h.totalBytes += c.upBytes + c.downBytes
                h.connectionIds.append(c.id)
                if c.startedAt > h.lastSeenAt {
                    h.lastSeenAt = c.startedAt; h.scene = c.scene; h.node = c.node
                }
                byHost[key] = h
            } else {
                order.append(key)
                byHost[key] = RecentHost(host: key, scene: c.scene, node: c.node, connections: 1,
                                         totalBytes: c.upBytes + c.downBytes, lastSeenAt: c.startedAt, connectionIds: [c.id])
            }
        }
        let all = order.compactMap { byHost[$0] }
        return Array(all.sorted {
            $0.lastSeenAt != $1.lastSeenAt ? $0.lastSeenAt > $1.lastSeenAt : $0.totalBytes > $1.totalBytes
        }.prefix(max(0, limit)))
    }
}
