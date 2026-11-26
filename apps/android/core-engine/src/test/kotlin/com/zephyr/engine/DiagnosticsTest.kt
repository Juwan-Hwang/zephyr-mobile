package com.zephyr.engine

import com.zephyr.engine.core.CoreEngine
import com.zephyr.engine.mock.MockEngine
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test

/** Contract §22.b: the no-core fallback for `redactDiagnostic` has the core's shape (core-mobile diagnostic.rs tests). */
class DiagnosticsTest {
    @Test fun redactsUrlsFoldsAndTruncates() {
        val r = Diagnostics.fallbackRedact("fetch  failed:\n https://user:pw@sub.example.com/api/subscribe?token=SECRET （超时）")
        assertFalse(r, r.contains("SECRET") || r.contains("pw@") || r.contains("subscribe"))
        assertTrue(r, r.startsWith("fetch failed: https://sub.example.com"))
        assertTrue(r, r.endsWith("（超时）"))
        assertFalse(r.contains('\n') || r.contains("  "))
        assertEquals("geodata missing: GeoSite.dat", Diagnostics.fallbackRedact(" geodata missing:\n  GeoSite.dat "))
        assertEquals("http://1.2.3.4:8080", Diagnostics.fallbackRedact("http://1.2.3.4:8080"))
        val long = Diagnostics.fallbackRedact("错".repeat(300))
        assertEquals(Diagnostics.MAX_CHARS + 1, long.codePointCount(0, long.length))
        assertTrue(long.endsWith("…"))
        assertEquals("", Diagnostics.fallbackRedact(""))
    }

    @Test fun enginesWithoutCoreUseTheFallback() {
        val text = "zm_start: GET https://x.example/sub?token=S failed"
        val mock = MockEngine(clock = { 0L })
        val core = CoreEngine(MockEngine(clock = { 0L }), mockData = false)
        assertEquals(Diagnostics.fallbackRedact(text), mock.redactDiagnostic(text))
        assertEquals(Diagnostics.fallbackRedact(text), core.redactDiagnostic(text))
        assertFalse(core.redactDiagnostic(text).contains("token"))
    }

    /** Without the native core: the mock catalogue answers when it stands in, otherwise nothing fake (core_crashed). */
    @Test fun setActiveSubscriptionWithoutCore() = runBlocking {
        val demo = CoreEngine(MockEngine(clock = { 0L }, latencyScale = 0.0), mockData = true)
        assertEquals("orbit", demo.setActiveSubscription("orbit").first().id)
        val release = CoreEngine(MockEngine(clock = { 0L }), mockData = false)
        try { release.setActiveSubscription("orbit"); fail("should throw") } catch (x: ZephyrException) {
            assertEquals(ErrorCode.CORE_CRASHED, x.code)
        }
    }
}
