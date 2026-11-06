package com.zephyr.engine.mock

import com.zephyr.engine.*

/**
 * Hand-authored fixed values from the prototype (contract/mock-spec.md §5–6).
 * Scene-pool nodes live outside the catalogue id space (≥ [POOL_BASE]).
 */
internal object MockScenes {
    const val POOL_BASE = 9_000_000_000L

    private class PoolNode(val summary: NodeSummary, val ip: String, val latency: Int)

    private var seq = 0L
    private fun n(region: String, city: String, name: String, ip: String, latency: Int, protocol: String = "VLESS", tag: String? = "IPLC"): PoolNode =
        PoolNode(NodeSummary(POOL_BASE + seq++, name, region, city, null, tag, protocol, null, latency), ip, latency)

    private val POOL: List<PoolNode> = listOf(
        n("SG", "新加坡", "新加坡 01", "198.51.100.6", 71),
        n("SG", "新加坡", "新加坡 02", "198.51.100.7", 63),
        n("SG", "新加坡", "新加坡 03", "198.51.100.8", 88, "Hy2"),
        n("JP", "东京", "东京 01", "203.0.113.59", 66),
        n("JP", "东京", "东京 02", "203.0.113.60", 74, "TUIC"),
        n("JP", "东京", "东京 03", "203.0.113.61", 61),
        n("JP", "大阪", "大阪 01", "203.0.113.70", 79, "Hy2"),
        n("HK", "香港", "香港 HKT", "203.0.113.24", 38, tag = "原生"),
        n("HK", "香港", "香港 HKBN", "203.0.113.25", 42, tag = "家宽"),
        n("HK", "香港", "香港 PCCW", "203.0.113.26", 47),
        n("TW", "台北", "TW-Fixed-01", "198.51.100.41", 48, "Trojan", "原生"),
        n("TW", "台北", "台北 HiNet 01", "198.51.100.42", 52),
        n("US", "洛杉矶", "US-Fixed-01", "203.0.113.24", 152, "Trojan", "原生"),
        n("US", "圣何塞", "圣何塞 01", "203.0.113.90", 164, "TUIC"),
        n("KR", "首尔", "首尔 01", "198.51.100.77", 69),
    )
    private val BY_ID = POOL.associateBy { it.summary.id }

    val SG_02 = POOL[1].summary
    val TOKYO_03 = POOL[5].summary
    val HK_HKT = POOL[7].summary
    val TW_FIXED = POOL[10].summary
    val US_FIXED = POOL[12].summary

    fun byId(id: Long): NodeSummary? = BY_ID[id]?.summary
    fun exitIp(id: Long): String? = BY_ID[id]?.ip
    fun latency(id: Long): Int? = BY_ID[id]?.latency

    fun pool(region: String?): List<NodeSummary> =
        POOL.map { it.summary }.filter { region == null || it.region.equals(region, ignoreCase = true) }

    fun initial(now: Long): List<Scene> {
        val tested = now - 2 * 3_600_000L
        return listOf(
            Scene("ai", SceneKind.AI, "AI", 9, SG_02, "198.51.100.7", SceneSource.AUTO, tested, null, listOf(SceneException("Claude", US_FIXED))),
            Scene("video", SceneKind.VIDEO, "视频", 22, HK_HKT, "203.0.113.24", SceneSource.AUTO, tested, "Netflix 完整片库"),
            Scene("other", SceneKind.OTHER, "其他", 0, TW_FIXED, "198.51.100.41", SceneSource.SUBSCRIPTION_GROUP, tested),
        )
    }
}

internal object MockSubscriptions {
    const val TOTAL_COUNT = 214
    private const val GB = 1_000_000_000L
    private const val DAY = 86_400_000L

    fun initial(now: Long): List<Subscription> = listOf(
        Subscription(
            id = "nebula", name = "Nebula Cloud", url = "https://nebula.example/api/v1/client/•••",
            nodeCount = 8_204, usedBytes = 113_600_000_000L, totalBytes = 200 * GB, remainingBytes = 86_400_000_000L,
            expiresAt = now + 26 * DAY, updatedAt = now - 2 * 3_600_000L, autoUpdateHours = 12,
            lastDiff = SubscriptionDiff(1_204, 318, 0, overridesKept = true, scenesRetested = true),
        ),
        Subscription(
            id = "orbit", name = "Orbit", url = "https://orbit.example/sub/•••",
            nodeCount = 3_118, usedBytes = 88 * GB, totalBytes = 100 * GB, remainingBytes = 12 * GB,
            expiresAt = now + 3 * DAY, updatedAt = now - 5 * 3_600_000L, autoUpdateHours = 12,
        ),
    )

    fun diffFor(s: Subscription): SubscriptionDiff {
        val h = MockCatalog.hsh(13, s.id.hashCode() and 0x7FFF_FFFF)
        return if (s.id == "nebula") SubscriptionDiff(1_204, 318, 0, true, true)
        else SubscriptionDiff(h % 40, h % 17, h % 3, true, true)
    }

    fun redact(url: String): String {
        val i = url.indexOf('?')
        val base = if (i >= 0) url.substring(0, i) else url
        val cut = base.lastIndexOf('/')
        return if (cut > 8) base.substring(0, cut + 1) + "•••" else base
    }
}

internal object MockGroups {
    fun initial(now: Long): List<PolicyGroup> = listOf(
        PolicyGroup("节点选择", GroupType.SELECT, "新加坡 02", 512, now - 2 * 3_600_000L),
        PolicyGroup("自动选择", GroupType.URL_TEST, "香港 HKT", 512, now - 600_000L),
        PolicyGroup("故障转移", GroupType.FALLBACK, "TW-Fixed-01", 64, now - 600_000L),
        PolicyGroup("AI", GroupType.SELECT, "新加坡 02", 138, now - 2 * 3_600_000L),
        PolicyGroup("流媒体", GroupType.SELECT, "香港 HKT", 96, now - 2 * 3_600_000L),
        PolicyGroup("负载均衡", GroupType.LOAD_BALANCE, null, 32, null),
    )

    /** Members interleave regions so every group shows a realistic mix. */
    fun member(group: String, k: Int): NodeSummary {
        val salt = group.hashCode() and 0xFF
        val r = (k + salt) % 6
        val j = k / 6 + salt
        return MockCatalog.summary(r, j)
    }
}

internal object MockConnections {
    private class C(val host: String, val scene: String?, val node: String, val down: Long, val up: Long)

    private val BASE = listOf(
        C("claude.ai", "AI", "US-Fixed-01", 2_100_000, 180_000),
        C("nflxvideo.net", "视频", "香港 HKT", 184_000_000, 2_400_000),
        C("gemini.google.com", "AI", "新加坡 02", 640_000, 90_000),
        C("github.com", "其他", "TW-Fixed-01", 12_000_000, 1_100_000),
        C("qq.com", null, "直连", 3_400_000, 410_000),
        C("api.openai.com", "AI", "新加坡 02", 1_300_000, 220_000),
        C("i.ytimg.com", "视频", "香港 HKT", 22_000_000, 300_000),
    )

    /** contract §13 fixed traces (prototype 9:41). */
    fun trace(host: String, now: Long): ConnectionTrace? {
        val i = BASE.indexOfFirst { it.host == host }.takeIf { it in 0..4 } ?: return null
        val c = BASE[i]
        return if (host == "claude.ai") ConnectionTrace(
            host = host, lastSeenAt = now - 3_000, connections = 17, totalBytes = 2_100_000,
            rule = "DOMAIN-SUFFIX,claude.ai", ruleSource = "Nebula Cloud", scene = "ai", sceneSource = "Zephyr 优选",
            node = NodeSummary(id = -101, name = "US-Fixed-01", region = "US", protocol = "VLESS", latencyMs = 162),
            via = "US Fixed IP · 固定", exitIp = "203.0.113.24", exitRegion = "美国", exitStableDays = 7,
        ) else ConnectionTrace(
            host = host, lastSeenAt = now - (i + 1) * 3_000L, connections = 3 + i * 2, totalBytes = c.down + c.up,
            rule = if (c.scene == null) "GEOSITE,cn" else "DOMAIN-SUFFIX,$host", ruleSource = if (c.scene == null) "geosite:cn" else "Nebula Cloud",
            scene = when (c.scene) { "AI" -> "ai"; "视频" -> "video"; "其他" -> "other"; else -> null },
            sceneSource = c.scene?.let { "Zephyr 优选" },
            node = c.scene?.let { NodeSummary(id = -102L - i, name = c.node, region = if (c.node.startsWith("TW")) "TW" else if (c.node.contains("香港")) "HK" else "SG", protocol = "VLESS") },
        )
    }

    fun at(start: Long, t: Long): List<ConnectionInfo> = BASE.mapIndexed { i, c ->
        val grow = 1.0 + t * (0.01 + i * 0.002)
        ConnectionInfo(
            id = "c$i", host = c.host, app = null, scene = c.scene, node = c.node,
            upBytes = (c.up * grow).toLong(), downBytes = (c.down * grow).toLong(), startedAt = start - (i + 1) * 3_000L,
        )
    }
}

internal object MockLogs {
    private val MSGS = listOf(
        LogLevel.INFO to "[TCP] 198.18.0.1:53412 --> claude.ai:443 match DomainSuffix(claude.ai) using AI[US-Fixed-01]",
        LogLevel.INFO to "[TCP] 198.18.0.1:53418 --> nflxvideo.net:443 match DomainSuffix(netflix.com) using 视频[香港 HKT]",
        LogLevel.DEBUG to "[DNS] github.com --> 140.82.112.4 (fake-ip 198.18.0.23)",
        LogLevel.INFO to "[UDP] 198.18.0.1:61001 --> 8.8.8.8:53 match Match using 其他[TW-Fixed-01]",
        LogLevel.WARNING to "[Provider] Orbit pull: 304 not modified",
        LogLevel.INFO to "[TCP] 198.18.0.1:53501 --> doubleclick.net:443 match DomainKeyword(doubleclick) using REJECT",
        LogLevel.ERROR to "[TCP] dial 新加坡 03 (198.51.100.8:443) error: i/o timeout",
    )

    fun line(i: Int, now: Long): LogLine {
        val (lvl, msg) = MSGS[(MockCatalog.hsh(9, i) % MSGS.size).toInt()]
        return LogLine(now, lvl, msg)
    }
}

internal object MockCommands {
    private val DOMAINISH = Regex("^[a-z0-9-]+(\\.[a-z0-9-]+)+$")
    private val SERVICES = mapOf("gemini" to "Gemini", "gpt" to "GPT", "chatgpt" to "GPT", "claude" to "Claude", "netflix" to "Netflix", "youtube" to "YouTube")

    fun suggest(raw: String, scenes: List<Scene>, conn: ConnectionState): List<CommandSuggestion> {
        val input = raw.trim().lowercase()
        val out = ArrayList<CommandSuggestion>()
        if (input.isEmpty()) {
            out += CommandSuggestion(
                CommandKind.TOGGLE_CONNECTION,
                if (conn.status == ConnectionStatus.CONNECTED) "断开连接" else "连接",
                null, "toggle",
            )
            out += CommandSuggestion(CommandKind.SWITCH_MODE, if (conn.mode == ProxyMode.GLOBAL) "使用规则模式" else "全局模式", null, if (conn.mode == ProxyMode.GLOBAL) "rule" else "global")
            out += CommandSuggestion(CommandKind.OPEN_NODE_QUERY, "最快的日本节点", "JP", "jp")
            out += CommandSuggestion(CommandKind.TEST_RULE, "claude.ai 走哪里？", null, "claude.ai")
            out += CommandSuggestion(CommandKind.OPEN_PAGE, "资料库", null, "library")
            return out
        }
        when {
            input in setOf("全局", "全局模式", "global") -> out += CommandSuggestion(CommandKind.SWITCH_MODE, "全局模式", "所有流量经由一个节点", "global")
            input in setOf("规则", "规则模式", "rule") -> out += CommandSuggestion(CommandKind.SWITCH_MODE, "规则模式", "按场景分流", "rule")
            input in setOf("直连", "direct") -> out += CommandSuggestion(CommandKind.SWITCH_MODE, "直连模式", "不经过代理", "direct")
        }
        if (DOMAINISH.matches(input) || MockRules.isIp(input)) {
            out += CommandSuggestion(CommandKind.TEST_RULE, "$input 走哪里？", "测试规则", input)
        }
        val service = SERVICES.entries.firstOrNull { input.contains(it.key) }?.value
        val q = NodeQuery.build(input.replace(Regex("走|用|使用|切到|换到"), " ").let { s -> SERVICES.keys.fold(s) { acc, k -> acc.replace(k, " ") } })
        if (q.groups.isNotEmpty() && q.highlights.isNotEmpty() && q.groups.size < MockCatalog.REGIONS.size) {
            val region = MockCatalog.REGIONS[q.groups.first().region]
            val pool = MockScenes.pool(region.code).sortedBy { it.latencyMs ?: Int.MAX_VALUE }
            val best = pool.firstOrNull()
            if (best != null) {
                val scene = if (service != null) scenes.firstOrNull { it.kind == SceneKind.AI || it.kind == SceneKind.VIDEO && service in setOf("Netflix", "YouTube") } else null
                out += CommandSuggestion(
                    CommandKind.SWITCH_NODE,
                    if (service != null) "$service 使用${region.name}节点" else "切换到 ${best.name}",
                    "${pool.size} 个可用，将使用 ${best.name}。",
                    "${scene?.id ?: "global"}:${best.id}",
                )
            }
            out += CommandSuggestion(CommandKind.OPEN_NODE_QUERY, "在节点库中查看「${q.highlights.joinToString(" ")}」", "%,d 个".format(q.total), q.query.trim())
        }
        return out.take(8)
    }
}
