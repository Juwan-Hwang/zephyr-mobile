package com.zephyr.app.vpn

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** Issue #208: a refused service start from the QS tile is reported and retried, never thrown out of the job. */
class ConnectionAttemptTest {
    private val reported = mutableListOf<String>()
    private val report: (String, Throwable) -> Unit = { w, t -> reported += "$w:${t.javaClass.simpleName}" }

    @Test fun startOkNoFallback() {
        var fell = false
        assertTrue(ConnectionController.attempt("start", start = {}, fallback = { fell = true }, report = report))
        assertFalse(fell); assertTrue(reported.isEmpty())
    }

    // android.app.ForegroundServiceStartNotAllowedException / BackgroundServiceStartNotAllowedException extend it.
    @Test fun refusedStartRunsFallback() {
        var fell = false
        assertFalse(ConnectionController.attempt("start", start = { throw IllegalStateException("not allowed") }, fallback = { fell = true }, report = report))
        assertTrue(fell); assertEquals(listOf("start:IllegalStateException"), reported)
    }

    @Test fun securityExceptionRunsFallback() {
        var fell = false
        ConnectionController.attempt("start", start = { throw SecurityException("type") }, fallback = { fell = true }, report = report)
        assertTrue(fell)
    }

    @Test fun failingFallbackIsReportedNotThrown() {
        ConnectionController.attempt("start", start = { throw IllegalStateException() }, fallback = { throw IllegalStateException("bal") }, report = report)
        assertEquals(listOf("start:IllegalStateException", "start (fallback):IllegalStateException"), reported)
    }
}
