package com.zephyr.engine.core

import com.zephyr.core.mobile.MihomoClient
import com.zephyr.engine.GroupType

/**
 * What [CoreEngine] needs from the running mihomo. Production: [RustLive] over core-mobile's
 * `MihomoClient` (unix-socket REST, shared with iOS). Tests: an in-memory fake, so the contract
 * mapping (scenes, ids, regions, empty/mock switching) is covered without the native library.
 *
 * All calls block; [CoreEngine] runs them on its IO dispatcher.
 */
interface LivePort {
    data class Group(val name: String, val type: GroupType, val selected: String?, val memberCount: Int, val testedAt: Long?)
    data class Member(val name: String, val type: String, val latencyMs: Int?)
    data class Conn(
        val id: String, val host: String, val app: String?, val scene: String?, val node: String,
        val up: Long, val down: Long, val startedAt: Long, val rule: String,
    )
    data class Host(val host: String, val scene: String?, val node: String, val connections: Int, val totalBytes: Long, val lastSeenAt: Long)
    data class Trace(
        val host: String, val lastSeenAt: Long, val connections: Int, val totalBytes: Long, val rule: String,
        val chain: List<String>, val scene: String?, val node: String,
    )

    /** In config order (GLOBAL excluded). */
    fun groups(): List<Group>
    fun members(group: String, offset: Int, limit: Int): List<Member>
    fun select(group: String, member: String)
    /** Delay per member, -1 = timeout. */
    fun test(group: String, url: String, timeoutMs: Int): List<Member>
    fun connections(limit: Int): List<Conn>
    fun hosts(limit: Int): List<Host>
    fun trace(host: String): Trace
    fun setMode(mode: String)
    fun close(id: String)
    fun closeAll()

    companion object { const val TEST_URL = "https://www.gstatic.com/generate_204" }
}

/** [LivePort] over the Rust client. Errors surface as `MobileException`, mapped by [CoreEngine]. */
class RustLive(socketPath: String) : LivePort {
    private val c = MihomoClient(socketPath)

    override fun groups() = c.policyGroups().map {
        LivePort.Group(it.name, type(it.groupType), it.selected, it.memberCount, it.testedAt)
    }
    override fun members(group: String, offset: Int, limit: Int) =
        c.groupMembers(group, offset.toUInt(), limit.toUInt()).map { LivePort.Member(it.name, it.proxyType, it.latencyMs) }
    override fun select(group: String, member: String) = c.selectInGroup(group, member)
    override fun test(group: String, url: String, timeoutMs: Int) =
        c.testGroup(group, url, timeoutMs.toUInt()).map { LivePort.Member(it.name, it.proxyType, it.latencyMs) }
    override fun connections(limit: Int) = c.activeConnections(limit.toUInt()).map {
        LivePort.Conn(it.id, it.host, it.app, it.scene, it.node, it.upBytes, it.downBytes, it.startedAt, it.rule)
    }
    override fun hosts(limit: Int) = c.recentHosts(limit.toUInt()).map {
        LivePort.Host(it.host, it.scene, it.node, it.connections, it.totalBytes, it.lastSeenAt)
    }
    override fun trace(host: String) = c.hostTrace(host).let {
        LivePort.Trace(it.host, it.lastSeenAt, it.connections, it.totalBytes, it.rule, it.chain, it.scene, it.node)
    }
    override fun setMode(mode: String) = c.setMode(mode)
    override fun close(id: String) = c.closeConnection(id)
    override fun closeAll() = c.closeAllConnections()

    private fun type(t: com.zephyr.core.mobile.GroupType) = when (t) {
        com.zephyr.core.mobile.GroupType.SELECT -> GroupType.SELECT
        com.zephyr.core.mobile.GroupType.URL_TEST -> GroupType.URL_TEST
        com.zephyr.core.mobile.GroupType.FALLBACK -> GroupType.FALLBACK
        com.zephyr.core.mobile.GroupType.LOAD_BALANCE -> GroupType.LOAD_BALANCE
        com.zephyr.core.mobile.GroupType.RELAY -> GroupType.RELAY
    }
}

/** Name-addressed helpers for live members (the core addresses library nodes by row id instead). */
object LiveNames {
    /** Stable negative id for a live member, disjoint from the core's non-negative ids. */
    fun idOf(name: String): Long {
        var h = -0x340d631b7bdddcdbL
        for (ch in name) { h = h xor ch.code.toLong(); h *= 0x100000001b3L }
        return -((h ushr 2) + 1)
    }

    fun isBuiltin(name: String) = name in BUILTIN
    private val BUILTIN = setOf("DIRECT", "REJECT", "REJECT-DROP", "PASS", "COMPATIBLE", "GLOBAL")

    /** Region code from a node name (live groups are small; the Rust core does this for the library). */
    fun regionOf(name: String): String {
        val n = name.uppercase()
        for ((code, keys) in REGION_KEYS) if (keys.any { k -> if (k.length <= 3 && k.all { it in 'A'..'Z' }) Regex("(^|[^A-Z])$k([^A-Z]|$)").containsMatchIn(n) else n.contains(k) }) return code
        return "UN"
    }

    private val REGION_KEYS = listOf(
        "HK" to listOf("香港", "HK", "HONG KONG", "🇭🇰"), "TW" to listOf("台湾", "台灣", "TW", "TAIWAN", "🇹🇼"),
        "JP" to listOf("日本", "东京", "大阪", "JP", "JAPAN", "TOKYO", "🇯🇵"), "SG" to listOf("新加坡", "狮城", "SG", "SINGAPORE", "🇸🇬"),
        "US" to listOf("美国", "洛杉矶", "圣何塞", "US", "USA", "UNITED STATES", "🇺🇸"), "KR" to listOf("韩国", "首尔", "KR", "KOREA", "🇰🇷"),
        "GB" to listOf("英国", "伦敦", "UK", "GB", "UNITED KINGDOM", "🇬🇧"), "DE" to listOf("德国", "法兰克福", "DE", "GERMANY", "🇩🇪"),
        "FR" to listOf("法国", "FR", "FRANCE", "🇫🇷"), "CA" to listOf("加拿大", "CANADA", "🇨🇦"), "AU" to listOf("澳大利亚", "澳洲", "AU", "AUSTRALIA", "🇦🇺"),
        "IN" to listOf("印度", "INDIA", "🇮🇳"), "TR" to listOf("土耳其", "TR", "TURKEY", "🇹🇷"), "RU" to listOf("俄罗斯", "RU", "RUSSIA", "🇷🇺"),
        "NL" to listOf("荷兰", "NL", "NETHERLANDS", "🇳🇱"),
    )
}
