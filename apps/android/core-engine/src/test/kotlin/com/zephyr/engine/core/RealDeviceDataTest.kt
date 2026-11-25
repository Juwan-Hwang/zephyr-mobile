package com.zephyr.engine.core

import com.zephyr.engine.LogLevel
import com.zephyr.engine.mock.MockEngine
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Assume.assumeTrue
import org.junit.Test
import java.nio.file.Files

/** Issue #1 (S25 Ultra, comment 7152702939): no mock data on a real device; library changes re-drive scenes / rules. */
class RealDeviceDataTest {

    @Test fun mockOnlyWithoutNativeLibrariesOrInDemo() {
        // debug + libraries loaded (real device) → real data
        assertFalse(CoreEngine.useMockData(debug = true, demo = false, nativeLoaded = true))
        // debug + libraries missing (JVM, emulator build without .so) → mock
        assertTrue(CoreEngine.useMockData(debug = true, demo = false, nativeLoaded = false))
        // demo mode always mocks
        assertTrue(CoreEngine.useMockData(debug = true, demo = true, nativeLoaded = true))
        // release never mocks, even without the libraries
        assertFalse(CoreEngine.useMockData(debug = false, demo = false, nativeLoaded = false))
        assertFalse(CoreEngine.useMockData(debug = false, demo = false, nativeLoaded = true))
    }

    @Test fun mockDataForDecidesAfterTheLibrariesTriedToLoad() {
        var seen: Boolean? = null
        val e = CoreEngine(MockEngine(clock = { 0L }), mockData = false, mockDataFor = { loaded -> seen = loaded; CoreEngine.useMockData(true, false, loaded) })
        assertEquals(false, seen) // no data dir / no .so on the JVM
        assertTrue(e.usesMockData)
        val release = CoreEngine(MockEngine(clock = { 0L }), mockData = true, mockDataFor = { CoreEngine.useMockData(false, false, it) })
        assertFalse(release.usesMockData)
        assertTrue(CoreEngine(MockEngine(clock = { 0L })).usesMockData) // no policy: constructor value
    }

    @Test fun withoutMockDataEverythingIsRealEmpty() = runBlocking {
        val e = CoreEngine(MockEngine(clock = { 0L }), mockData = false, tick = 10)
        assertEquals(emptyList<Any>(), e.scenes().first())
        val u = e.usageToday()
        assertEquals(0L, u.todayBytes); assertEquals(24, u.hourly.size); assertTrue(u.hourly.all { it == 0L })
        val r = e.ruleStats()
        assertEquals(0L, r.total); assertFalse(r.compiled)
    }

    @Test fun appLogLinesReachTheLogsStreamFilteredByLevel() = runBlocking {
        val e = CoreEngine(MockEngine(clock = { 0L }), mockData = false, tick = 10, clock = { 42L })
        e.appLog(LogLevel.DEBUG, "noise")
        e.appLog(LogLevel.ERROR, "connect failed [core_crashed]: geodata missing: GeoIP.dat")
        val line = withTimeout(2_000) { e.logs(LogLevel.WARNING).first() }
        assertEquals(LogLevel.ERROR, line.level)
        assertEquals(42L, line.at)
        assertTrue(line.message.contains("geodata missing:"))
    }

    /** Needs the host core (`-Pzephyr.coreLib=…`), like [CoreParityTest]. */
    @Test fun scenesAndRulesFollowLibraryChanges() = runBlocking {
        val lib = System.getProperty("zephyr.coreLib")?.takeIf { it.isNotBlank() }
        assumeTrue("set -Pzephyr.coreLib to run", lib != null)
        System.setProperty("uniffi.component.zephyr_mobile_core.libraryOverride", lib!!)
        val e = CoreEngine(MockEngine(clock = { 0L }), Files.createTempDirectory("zcore").toString(), mockData = false, tick = 10)
        check(e.isNative)
        val flow = e.scenes()
        assertEquals(emptyList<Any>(), flow.first()) // empty store: real empty, not mock
        e.seedMockNodes(0.05) // library changed → collectors re-check instead of staying empty
        val after = withTimeout(5_000) { flow.first { it.isNotEmpty() } }
        assertTrue(after.isNotEmpty())
    }
}
