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

    companion object {
        val QUERIES = listOf("", "JP", "东京", "日本 NTT", "HK HKT", "IPLC", "US 洛杉矶 CN2", "家宽", "TW-Fixed", "zzz-none")
    }
}
