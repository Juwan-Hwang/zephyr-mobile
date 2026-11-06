package com.zephyr.engine.core

import com.zephyr.engine.ErrorCode
import com.zephyr.engine.GroupType
import com.zephyr.engine.ZephyrException
import com.zephyr.engine.mock.MockEngine
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Before
import org.junit.Test
import java.net.ServerSocket
import java.net.Socket
import java.util.Collections
import kotlin.concurrent.thread

/** MihomoRest + CoreEngine live mapping against a fake mihomo controller speaking real HTTP/1.1. */
class MihomoRestTest {
    private lateinit var server: ServerSocket
    val requests: MutableList<String> = Collections.synchronizedList(mutableListOf())

    private val proxiesJson = """
      {"proxies":{
        "AI":{"type":"Selector","now":"US 洛杉矶 01","all":["US 洛杉矶 01","香港 HKT 02","DIRECT"],"history":[]},
        "视频":{"type":"URLTest","now":"香港 HKT 02","all":["香港 HKT 02"],"history":[]},
        "GLOBAL":{"type":"Selector","now":"AI","all":["DIRECT","AI","视频","US 洛杉矶 01"]},
        "US 洛杉矶 01":{"type":"Vless","history":[{"time":"2026-11-06T15:00:00.000+08:00","delay":162}]},
        "香港 HKT 02":{"type":"Shadowsocks","history":[{"time":"2026-11-06T15:00:01.000+08:00","delay":0}]},
        "DIRECT":{"type":"Direct","history":[]}
      }}""".trimIndent()

    private val connectionsJson = """
      {"downloadTotal":1,"uploadTotal":1,"connections":[
        {"id":"a1","metadata":{"host":"claude.ai","destinationIP":"160.79.104.10","process":"com.anthropic.claude"},"upload":100,"download":2000,
         "start":"2026-11-06T15:00:00.000+08:00","chains":["US 洛杉矶 01","AI"],"rule":"DomainSuffix","rulePayload":"claude.ai"},
        {"id":"a2","metadata":{"host":"claude.ai","destinationIP":"160.79.104.10"},"upload":50,"download":50,
         "start":"2026-11-06T15:00:03.000+08:00","chains":["US 洛杉矶 01","AI"],"rule":"DomainSuffix","rulePayload":"claude.ai"},
        {"id":"b1","metadata":{"host":"","destinationIP":"1.2.3.4"},"upload":1,"download":2,
         "start":"2026-11-06T15:00:01.000+08:00","chains":["DIRECT"],"rule":"GeoIP","rulePayload":"CN"}
      ]}""".trimIndent()

    @Before fun up() {
        server = ServerSocket(0)
        thread(isDaemon = true) {
            while (!server.isClosed) {
                val s = runCatching { server.accept() }.getOrNull() ?: break
                thread(isDaemon = true) { handle(s) }
            }
        }
    }

    @After fun down() { server.close() }

    private fun handle(s: Socket) = s.use {
        val r = s.getInputStream().bufferedReader()
        val line = r.readLine() ?: return
        var len = 0
        while (true) { val h = r.readLine() ?: break; if (h.isEmpty()) break; if (h.startsWith("Content-Length:")) len = h.substringAfter(':').trim().toInt() }
        val body = if (len > 0) CharArray(len).also { r.read(it) }.concatToString() else ""
        requests += "$line $body".trim()
        val path = line.split(' ')[1]
        val (code, payload, chunked) = when {
            path == "/proxies" -> Triple(200, proxiesJson, true)
            path == "/connections" && line.startsWith("GET") -> Triple(200, connectionsJson, false)
            path.startsWith("/group/AI/delay") -> Triple(200, """{"US 洛杉矶 01":158}""", false)
            path.startsWith("/group/") -> Triple(404, """{"message":"not found"}""", false)
            else -> Triple(204, "", false)
        }
        val out = s.getOutputStream()
        val bytes = payload.toByteArray()
        if (chunked) {
            out.write("HTTP/1.1 $code OK\r\nContent-Type: application/json\r\nTransfer-Encoding: chunked\r\n\r\n".toByteArray())
            bytes.toList().chunked(97).forEach { c -> out.write("${Integer.toHexString(c.size)}\r\n".toByteArray()); out.write(c.toByteArray()); out.write("\r\n".toByteArray()) }
            out.write("0\r\n\r\n".toByteArray())
        } else {
            out.write("HTTP/1.1 $code X\r\nContent-Length: ${bytes.size}\r\n\r\n".toByteArray()); out.write(bytes)
        }
        out.flush()
    }

    private fun rest() = MihomoRest {
        val s = Socket("127.0.0.1", server.localPort)
        object : MihomoRest.Conn { override val input = s.getInputStream(); override val output = s.getOutputStream(); override fun close() = s.close() }
    }

    @Test fun parsesProxiesAndConnections() {
        val r = rest()
        val p = r.proxies()
        assertEquals("US 洛杉矶 01", p["AI"]!!.now)
        assertEquals(162, p["US 洛杉矶 01"]!!.lastDelay)
        val cs = r.connections()
        assertEquals(3, cs.size)
        assertEquals("1.2.3.4", cs[2].host)
        assertEquals("com.anthropic.claude", cs[0].process)
        assertEquals("DOMAIN-SUFFIX,claude.ai", MihomoRest.ruleText(cs[0].rule, cs[0].rulePayload))
        assertEquals("MATCH", MihomoRest.ruleText("Match", ""))
    }

    @Test fun regionAndIds() {
        assertEquals("US", MihomoRest.regionOf("US 洛杉矶 01"))
        assertEquals("HK", MihomoRest.regionOf("🇭🇰 香港 HKT"))
        assertEquals("JP", MihomoRest.regionOf("JP-Tokyo-NTT"))
        assertEquals("UN", MihomoRest.regionOf("LINE 专线"))
        assertTrue(MihomoRest.idOf("a") < 0)
        assertEquals(MihomoRest.idOf("香港 HKT 02"), MihomoRest.idOf("香港 HKT 02"))
    }

    @Test fun engineMapsLiveController() = runBlocking {
        val r = rest()
        val e = CoreEngine(MockEngine(clock = { 0L }), live = { r }, tick = 20, mockData = false)
        val groups = e.policyGroups().first()
        assertEquals(listOf("AI", "视频"), groups.map { it.name }) // GLOBAL hidden
        assertEquals(GroupType.URL_TEST, groups[1].type)
        val members = e.groupMembers("AI", 0, 50)
        assertEquals(3L, members.total)
        assertEquals("US", members.rows[0].region); assertEquals(162, members.rows[0].latencyMs)
        assertNull(members.rows[1].latencyMs) // delay 0 = timeout
        e.selectInGroup("AI", members.rows[1].id)
        assertTrue(requests.any { it.startsWith("PUT /proxies/AI ") && it.contains("\"name\":\"香港 HKT 02\"") })
        e.testGroup("AI")
        try { e.testGroup("nope"); fail() } catch (x: ZephyrException) { assertEquals(ErrorCode.GROUP_NOT_FOUND, x.code) }

        val scenes = e.scenes().first()
        assertEquals(listOf("AI", "视频"), scenes.map { it.name })
        assertEquals(com.zephyr.engine.SceneKind.AI, scenes[0].kind); assertEquals(com.zephyr.engine.SceneKind.VIDEO, scenes[1].kind)
        assertEquals(2, scenes[0].available) // DIRECT excluded
        assertEquals("US 洛杉矶 01", scenes[0].selected.name)
        val cands = e.sceneCandidates("AI", null)
        assertEquals("US 洛杉矶 01", cands[0].name) // tested first, timeout last
        assertEquals("HK", e.previewSceneChange("AI", cands[1].id).toRegion)
        e.applySceneChange("AI", cands[1].id)

        val conns = e.activeConnections().first()
        assertEquals("AI", conns[0].scene); assertEquals("US 洛杉矶 01", conns[0].node)
        assertNull(conns[2].scene); assertEquals("直连", conns[2].node)
        val hosts = e.recentHosts(5).first()
        assertEquals(listOf("claude.ai", "1.2.3.4"), hosts.map { it.host })
        assertEquals(2200L, hosts[0].downBytes + hosts[0].upBytes)
        val t = e.connectionTrace("claude.ai")
        assertEquals(2, t.connections); assertEquals("DOMAIN-SUFFIX,claude.ai", t.rule); assertEquals("AI", t.scene)
        e.setMode(com.zephyr.engine.ProxyMode.GLOBAL)
        assertTrue(requests.any { it.startsWith("PATCH /configs") && it.contains("global") })
        e.closeAll()
        assertTrue(requests.any { it.startsWith("DELETE /connections ") || it == "DELETE /connections HTTP/1.1" })
    }

    @Test fun releaseWithoutCoreShowsNothingFake() = runBlocking {
        val e = CoreEngine(MockEngine(clock = { 0L }), live = { null }, mockData = false)
        assertEquals(emptyList<Any>(), e.policyGroups().first())
        assertEquals(emptyList<Any>(), e.activeConnections().first())
        assertEquals(0L, e.nodeIndex().total)
    }
}
