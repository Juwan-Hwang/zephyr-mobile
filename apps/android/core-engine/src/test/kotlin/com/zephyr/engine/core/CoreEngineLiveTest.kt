package com.zephyr.engine.core

import com.zephyr.engine.ErrorCode
import com.zephyr.engine.GroupType
import com.zephyr.engine.ProxyMode
import com.zephyr.engine.ZephyrException
import com.zephyr.engine.mock.MockEngine
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test

/** Contract mapping on top of a running mihomo (fake [LivePort]; the Rust client itself is tested in core-mobile). */
class CoreEngineLiveTest {
    private class Fake : LivePort {
        val calls = mutableListOf<String>()
        var selected = mutableMapOf("AI" to "US 洛杉矶 01", "视频" to "HK-Auto", "HK-Auto" to "香港 HKT 02")
        val members = mapOf(
            "AI" to listOf(LivePort.Member("US 洛杉矶 01", "Vless", 162), LivePort.Member("香港 HKT 02", "Shadowsocks", -1), LivePort.Member("DIRECT", "Direct", null)),
            "视频" to listOf(LivePort.Member("HK-Auto", "URLTest", null)),
            "HK-Auto" to listOf(LivePort.Member("香港 HKT 02", "Shadowsocks", -1)),
        )
        override fun groups() = listOf(
            LivePort.Group("AI", GroupType.SELECT, selected["AI"], 3, 1_000),
            LivePort.Group("视频", GroupType.SELECT, selected["视频"], 1, null),
            LivePort.Group("HK-Auto", GroupType.URL_TEST, selected["HK-Auto"], 1, null),
        )
        override fun members(group: String, offset: Int, limit: Int) =
            (members[group] ?: throw com.zephyr.core.mobile.MobileException.NotFound(group)).drop(offset).take(limit)
        override fun select(group: String, member: String) { calls += "select $group=$member"; selected[group] = member }
        override fun test(group: String, url: String, timeoutMs: Int) =
            members[group]?.map { it.copy(latencyMs = 150) } ?: throw com.zephyr.core.mobile.MobileException.NotFound(group)
        override fun connections(limit: Int) = listOf(
            LivePort.Conn("a1", "claude.ai", "com.anthropic.claude", "AI", "US 洛杉矶 01", 100, 2000, 3_000, "DOMAIN-SUFFIX,claude.ai"),
            LivePort.Conn("b1", "qq.com", null, null, "DIRECT", 1, 2, 1_000, "GEOSITE,cn"),
        )
        override fun hosts(limit: Int) = listOf(LivePort.Host("claude.ai", "AI", "US 洛杉矶 01", 17, 2_100_000, 3_000), LivePort.Host("qq.com", null, "DIRECT", 2, 3, 1_000)).take(limit)
        override fun trace(host: String) = if (host == "claude.ai")
            LivePort.Trace(host, 3_000, 17, 2_100_000, "DOMAIN-SUFFIX,claude.ai", listOf("AI", "US Fixed IP", "US-Fixed-01"), "AI", "US-Fixed-01")
        else throw com.zephyr.core.mobile.MobileException.NotFound(host)
        override fun setMode(mode: String) { calls += "mode $mode" }
        override fun close(id: String) { calls += "close $id" }
        override fun closeAll() { calls += "closeAll" }
    }

    @Test fun mapsLiveCore() = runBlocking {
        val f = Fake()
        val e = CoreEngine(MockEngine(clock = { 0L }), live = { f }, tick = 10, mockData = false, clock = { 9_000L })

        val page = e.groupMembers("AI", 0, 50)
        assertEquals(3L, page.total); assertEquals("直连", page.rows[2].name)
        try { e.groupMembers("nope", 0, 5); fail() } catch (x: ZephyrException) { assertEquals(ErrorCode.GROUP_NOT_FOUND, x.code) }
        try { e.testGroup("nope"); fail() } catch (x: ZephyrException) { assertEquals(ErrorCode.GROUP_NOT_FOUND, x.code) }

        val conns = e.activeConnections().first()
        assertEquals("com.anthropic.claude", conns[0].app); assertEquals("直连", conns[1].node); assertNull(conns[1].scene)
        val hosts = e.recentHosts(5).first()
        assertEquals(2_100_000L, hosts[0].downBytes + hosts[0].upBytes)
        val t = e.connectionTrace("claude.ai")
        assertEquals("US Fixed IP", t.via); assertEquals("US-Fixed-01", t.node?.name); assertEquals("US", t.node?.region)

        e.setMode(ProxyMode.GLOBAL); e.closeAll(); e.closeConnection("a1")
        assertTrue(listOf("mode global", "closeAll", "close a1").all { it in f.calls })
        assertEquals(listOf("AI", "视频", "HK-Auto"), e.policyGroups().first().map { it.name })
    }

    @Test fun releaseWithoutCoreShowsNothingFake() = runBlocking {
        val e = CoreEngine(MockEngine(clock = { 0L }), live = { null }, mockData = false)
        assertEquals(0, e.scenes().first().size)
        assertEquals(0, e.activeConnections().first().size)
        assertEquals(0, e.subscriptions().first().size)
        assertEquals(0L, e.nodeIndex().total)
    }

    @Test fun regions() {
        assertEquals("US", LiveNames.regionOf("US 洛杉矶 01"))
        assertEquals("HK", LiveNames.regionOf("🇭🇰 香港 HKT"))
        assertEquals("JP", LiveNames.regionOf("JP-Tokyo-NTT"))
        assertEquals("UN", LiveNames.regionOf("LINE 专线"))
        assertTrue(LiveNames.idOf("a") < 0)
    }
}
