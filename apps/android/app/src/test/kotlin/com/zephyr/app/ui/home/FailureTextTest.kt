package com.zephyr.app.ui.home

import com.zephyr.app.R
import com.zephyr.engine.ErrorCode
import com.zephyr.engine.ZephyrError
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** Issue #1: failure hint + expandable detail line under "连接失败". */
class FailureTextTest {
    @Test fun geodataMissingGetsItsOwnHint() {
        assertEquals(R.string.home_failure_geodata, failureText(ZephyrError(ErrorCode.CORE_CRASHED, "geodata missing: GeoSite.dat")))
        assertEquals(R.string.home_failure_core, failureText(ZephyrError(ErrorCode.CORE_CRASHED, "zm_start failed")))
        assertEquals(R.string.home_failure_no_subscription, failureText(ZephyrError(ErrorCode.SUBSCRIPTION_NOT_FOUND, "x")))
        assertEquals(R.string.home_failure_core, failureText(null as ZephyrError?))
    }

    /** Contract §22.b: the detail is only the redactor's output (core redactDiagnostic); the platform no longer folds or cuts. */
    @Test fun detailGoesThroughTheRedactor() {
        val seen = mutableListOf<String>()
        val d = failureDetail(ZephyrError(ErrorCode.CORE_CRASHED, "fetch https://x/sub?token=S")) { seen += it; "R" }
        assertEquals(listOf("fetch https://x/sub?token=S"), seen)
        assertEquals("R", d)
        assertEquals(500, failureDetail(ZephyrError(ErrorCode.CORE_CRASHED, "x".repeat(500))) { it }?.length)
        assertNull(failureDetail(ZephyrError(ErrorCode.CORE_CRASHED, " \n ")) { it })
        assertNull("nothing left after redaction → no detail line", failureDetail(ZephyrError(ErrorCode.CORE_CRASHED, "x")) { " " })
    }

    @Test fun defaultRedactorIsTheNoCoreFallback() {
        val d = failureDetail(ZephyrError(ErrorCode.CORE_CRASHED, " geodata missing:\n  GeoIP.dat ")) { com.zephyr.engine.Diagnostics.fallbackRedact(it) }
        assertEquals("geodata missing: GeoIP.dat", d)
        val long = failureDetail(ZephyrError(ErrorCode.CORE_CRASHED, "x".repeat(1_000)), com.zephyr.engine.Diagnostics::fallbackRedact)!!
        assertEquals(com.zephyr.engine.Diagnostics.MAX_CHARS + 1, long.length)
        assertTrue(long.endsWith("…"))
    }
}
