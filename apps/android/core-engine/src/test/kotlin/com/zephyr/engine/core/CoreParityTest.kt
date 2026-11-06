package com.zephyr.engine.core

import com.zephyr.engine.mock.MockEngine
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

    /** Real import path end-to-end on the host .so: ProfileStore → Rust rebuildNodes + prepareRuntimeConfig. */
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
        val store = ProfileStore(dir, fetch = { ProfileStore.Fetched(yaml, "upload=1; download=2; total=3", null) })
        val core = CoreEngine(MockEngine(clock = { 0L }), java.io.File(dir, "core").apply { mkdirs() }.path, profiles = store)
        check(core.isNative)
        val sub = core.importSubscription(com.zephyr.engine.ImportSource.URL, "https://sub.example.com/x?token=t")
        assertEquals(3L, sub.nodeCount, "rust node count")
        assertEquals(3L, core.nodeIndex().total)
        assertEquals(1L, core.queryNodes("东京").total)
        val active = store.activeFile.readText()
        val secret = java.io.File(dir, "profiles/secret").readText()
        kotlin.test.assertTrue(active.contains("127.0.0.1:"), "controller forced to localhost")
        kotlin.test.assertTrue(active.contains(secret), "secret injected")
        val withFd = uniffi.zephyr_core.injectTunFd(active, 42)
        kotlin.test.assertTrue(withFd.contains("42"), "tun fd injected")
        println("active.yaml ${active.length} B, tun:\n" + withFd.lines().dropWhile { !it.startsWith("tun:") }.take(8).joinToString("\n"))
    }

    companion object {
        val QUERIES = listOf("", "JP", "东京", "日本 NTT", "HK HKT", "IPLC", "US 洛杉矶 CN2", "家宽", "TW-Fixed", "zzz-none")
    }
}
