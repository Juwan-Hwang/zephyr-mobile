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

    @Test fun detailIsTheMessageFoldedAndTruncated() {
        assertNull(failureDetail(ZephyrError(ErrorCode.CORE_CRASHED, "  ")))
        assertEquals("geodata missing: GeoIP.dat", failureDetail(ZephyrError(ErrorCode.CORE_CRASHED, " geodata missing:\n  GeoIP.dat ")))
        val long = failureDetail(ZephyrError(ErrorCode.CORE_CRASHED, "x".repeat(1_000)))!!
        assertEquals(FAILURE_DETAIL_MAX_CHARS, long.length)
        assertTrue(long.endsWith("…"))
    }
}
