package com.zephyr.engine.core

import com.zephyr.engine.mock.MockEngine
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import org.junit.Assume.assumeTrue
import org.junit.Test
import java.nio.file.Files
import kotlin.test.assertEquals

/**
 * Kotlin MockEngine vs Rust core (host build of core-mobile through the generated UniFFI bindings):
 * same catalogue → same totals, sections and first rows for every query. Proves the FFI mapping and that
 * both platforms see identical data. Runs only when `-Pzephyr.coreLib=/path/libzephyr_mobile_core.so`.
 */
class CoreParityTest {
    private val lib: String? = System.getProperty("zephyr.coreLib")?.takeIf { it.isNotBlank() }

    @Test
    fun parityWithMock() = runBlocking {
        assumeTrue("set -Pzephyr.coreLib to run", lib != null)
        System.setProperty("uniffi.component.zephyr_mobile_core.libraryOverride", lib!!)
        val mock = MockEngine(clock = { 0L })
        val core = CoreEngine(mock, Files.createTempDirectory("zcore").toString())
        check(core.isNative) { "native core failed to load from $lib" }
        val t0 = System.nanoTime()
        core.seedMockNodes(1.0)
        println("core: seeded full catalogue in ${(System.nanoTime() - t0) / 1_000_000} ms")

        val ci = core.nodeIndex(); val mi = mock.nodeIndex()
        assertEquals(mi.total, ci.total, "total")
        assertEquals(mi.sections.map { it.region to it.count }, ci.sections.map { it.region to it.count }, "sections")

        for (q in QUERIES) {
            val m = mock.queryNodes(q); val c = core.queryNodes(q)
            assertEquals(m.total, c.total, "total for '$q'")
            assertEquals(m.sections.map { it.region to it.count }, c.sections.map { it.region to it.count }, "sections for '$q'")
            val mr = mock.nodeRows(m.token, 0, 12).rows.map { it.name }
            val cr = core.nodeRows(c.token, 0, 12).rows.map { it.name }
            assertEquals(mr, cr, "first rows for '$q'")
            println("'$q': ${c.total} in ${c.tookMicros} µs (mock ${m.tookMicros} µs)")
        }
    }

    /** Real import path end-to-end on the host .so: fetch (injected) → core importSubscription → runtimeConfig. */
    @Test
    fun nativeProfileImport() = runBlocking {
        assumeTrue("set -Pzephyr.coreLib to run", lib != null)
        System.setProperty("uniffi.component.zephyr_mobile_core.libraryOverride", lib!!)
        System.setProperty("uniffi.component.zephyr_core.libraryOverride", lib)
        val dir = Files.createTempDirectory("zprof").toFile()
        val yaml = """
            proxies:
              - {name: 香港 HKT 01, type: ss, server: hk1.example.com, port: 443, cipher: aes-128-gcm, password: x}
              - {name: 日本 东京 NTT 01, type: ss, server: jp1.example.com, port: 443, cipher: aes-128-gcm, password: x}
              - {name: US 洛杉矶 CN2 01, type: ss, server: us1.example.com, port: 443, cipher: aes-128-gcm, password: x}
            proxy-groups:
              - {name: AI, type: select, proxies: [US 洛杉矶 CN2 01]}
            rules:
              - MATCH,AI
        """.trimIndent()
        val core = CoreEngine(
            MockEngine(clock = { 0L }), dir.path, mockData = false,
            fetcher = { SubscriptionFetcher.Fetched(yaml, "upload=1; download=2; total=3", null) },
        )
        check(core.isNative)
        val sub = core.importSubscription(com.zephyr.engine.ImportSource.URL, "https://sub.example.com/x?token=t")
        assertEquals(3L, sub.nodeCount, "rust node count")
        kotlin.test.assertFalse(sub.url!!.contains("token"), "url redacted")
        assertEquals(sub.id, core.activeSubscription())
        assertEquals(3L, core.nodeIndex().total)
        assertEquals(1L, core.queryNodes("东京").total)
        val cfg = core.runtimeConfig(42, "/tmp/zm.sock", com.zephyr.engine.Settings(), com.zephyr.engine.ProxyMode.RULE)!!
        kotlin.test.assertTrue(cfg.contains("/tmp/zm.sock"), "unix controller")
        kotlin.test.assertTrue(Regex("file-descriptor:\\s*42").containsMatchIn(cfg), "tun fd")
        println("runtime config ${cfg.length} B:\n" + cfg.lines().filter { it.startsWith("tun:") || it.startsWith("  ") }.take(14).joinToString("\n"))
        kotlin.test.assertTrue(Regex("(?m)^proxy-groups:").containsMatchIn(cfg), "groups")
        val scenes = core.scenes().first()
        println("scenes: " + scenes.joinToString { "${it.id}/${it.kind}/${it.name}/${it.selected.name}/${it.available}" })
        kotlin.test.assertTrue(scenes.isNotEmpty(), "core scenes")
        val oldQ = core.queryNodes("香港")
        val sub2 = core.importSubscription(com.zephyr.engine.ImportSource.CLIPBOARD, yaml.replace("hk1", "hk2").replace("香港 HKT 01", "香港 HKT 09"))
        val after = core.nodeRows(oldQ.token, 0, 10) // rebuilt store → stale token → silent requery
        assertEquals(2L, after.total, "requeried after rebuild")
        val pick = core.queryNodes("东京").let { q -> core.nodeRows(q.token, 0, 1).rows.single() }
        val x = core.previewSceneChange(scenes[0].id, pick.id)
        assertEquals("JP", x.toRegion)
        core.applySceneChange(scenes[0].id, pick.id)
        assertEquals("日本 东京 NTT 01", core.scenes().first().first { it.id == scenes[0].id }.selected.name)
        core.overrideHost("claude.ai", com.zephyr.engine.TraceTarget.DIRECT, null, persistent = false)
        core.deleteSubscription(sub.id)
        assertEquals(sub2.id, core.activeSubscription(), "active falls over to the remaining subscription")
        core.deleteSubscription(sub2.id)
        assertEquals(null, core.activeSubscription())
    }

    companion object {
        val QUERIES = listOf("", "JP", "东京", "日本 NTT", "HK HKT", "IPLC", "US 洛杉矶 CN2", "家宽", "TW-Fixed", "zzz-none")
    }

    /** §14.u: tunnel down → TCP handshake targets from core (hosts unmasked), results written back to the cache. */
    @Test
    fun tcpPingWhenDisconnected() = runBlocking {
        assumeTrue("set -Pzephyr.coreLib to run", lib != null)
        System.setProperty("uniffi.component.zephyr_mobile_core.libraryOverride", lib!!)
        System.setProperty("uniffi.component.zephyr_core.libraryOverride", lib)
        val dir = Files.createTempDirectory("ztcp").toFile()
        val yaml = """
            proxies:
              - {name: HK 01, type: ss, server: hk1.example.com, port: 443, cipher: aes-128-gcm, password: x}
              - {name: JP 01, type: hysteria2, server: jp1.example.com, port: 443, password: x}
        """.trimIndent()
        val pinged = mutableListOf<Pair<String, Int>>()
        val core = CoreEngine(
            MockEngine(clock = { 0L }), dir.path, mockData = false, clock = { 1_000L },
            fetcher = { SubscriptionFetcher.Fetched(yaml, null, null) },
            tcpPing = { h, p -> synchronized(pinged) { pinged += h to p }; 42 },
        )
        core.importSubscription(com.zephyr.engine.ImportSource.URL, "https://sub.example.com/t")
        val q = core.queryNodes("")
        val ids = core.nodeRows(q.token, 0, 10).rows.map { it.id }
        assertEquals(2, ids.size)
        core.testLatency(ids)
        assertEquals(listOf("hk1.example.com" to 443), pinged, "UDP protocol skipped, host unmasked")
        assertEquals(1L, core.nodeIndex().testedCount)
    }
}
