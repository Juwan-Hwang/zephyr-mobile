package com.zephyr.app.ui.settings

import com.zephyr.engine.LogLevel
import com.zephyr.engine.LogLine
import com.zephyr.engine.ZephyrEngine
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.lang.reflect.Proxy
import java.util.TimeZone

class LogsModelTest {
    private val utc = TimeZone.getTimeZone("UTC")

    /** Engine stub: only logs() is used; it echoes the requested level so re-subscription is observable. */
    private fun engine(lines: (LogLevel) -> List<LogLine>): ZephyrEngine =
        Proxy.newProxyInstance(ZephyrEngine::class.java.classLoader, arrayOf(ZephyrEngine::class.java)) { _, m, args ->
            if (m.name == "logs") flowOf(*lines(args!![0] as LogLevel).toTypedArray()) else throw UnsupportedOperationException(m.name)
        } as ZephyrEngine

    private fun line(i: Int, l: LogLevel = LogLevel.INFO) = LogLine(i.toLong(), l, "m$i")

    @Test fun formatIsTimeBadgeMessage() {
        assertEquals("01:02:03.004 W hello", LogsModel.format(LogLine(3_723_004L, LogLevel.WARNING, "hello"), utc))
        assertEquals(listOf("D", "I", "W", "E"), LogLevel.entries.map(LogsModel::badge))
    }

    @Test fun capacityKeepsNewest() {
        val m = LogsModel(engine { emptyList() }, TestScope())
        repeat(LogsModel.CAPACITY + 20) { m.append(line(it)) }
        assertEquals(LogsModel.CAPACITY, m.lines.value.size)
        assertEquals("m20", m.lines.value.first().message)
    }

    @Test fun pauseStopsAppendingAndClearEmpties() {
        val m = LogsModel(engine { emptyList() }, TestScope())
        m.append(line(1)); m.togglePause(); m.append(line(2))
        assertEquals(1, m.lines.value.size)
        m.clear()
        assertTrue(m.lines.value.isEmpty())
    }

    @Test fun levelChangeResubscribes() = runTest {
        val m = LogsModel(engine { l -> listOf(line(l.ordinal, l)) }, this)
        m.start(); advanceUntilIdle()
        assertEquals(listOf(LogLevel.INFO), m.lines.value.map { it.level })
        m.setLevel(LogLevel.ERROR); advanceUntilIdle()
        assertEquals(listOf(LogLevel.ERROR), m.lines.value.map { it.level })
        assertEquals("00:00:00.003 E m3", m.exportText(utc))
        m.stop()
    }
    /** Contract §16.h: debug segment raises mihomo to debug, leaving it (or the page) goes back to info. */
    @Test fun debugSegmentDrivesMihomoLevel() = runTest {
        val calls = mutableListOf<LogLevel>()
        val e = Proxy.newProxyInstance(ZephyrEngine::class.java.classLoader, arrayOf(ZephyrEngine::class.java)) { _, m, args ->
            when (m.name) {
                "logs" -> flowOf<LogLine>()
                "setLogLevel" -> { calls += args!![0] as LogLevel; Unit }
                else -> throw UnsupportedOperationException(m.name)
            }
        } as ZephyrEngine
        val m = LogsModel(e, this)
        m.start()
        m.setLevel(LogLevel.WARNING); advanceUntilIdle()
        assertEquals(emptyList<LogLevel>(), calls) // warning / error only filter the display
        m.setLevel(LogLevel.DEBUG); advanceUntilIdle()
        m.setLevel(LogLevel.INFO); advanceUntilIdle()
        m.setLevel(LogLevel.DEBUG); advanceUntilIdle()
        m.stop(); advanceUntilIdle()
        assertEquals(listOf(LogLevel.DEBUG, LogLevel.INFO, LogLevel.DEBUG, LogLevel.INFO), calls)
    }
}

/** Contract §16.c shareDiagnostics: the summary never carries trustedWifi; codes only. */
class DiagnosticsSummaryTest {
    @org.junit.Test fun summaryOmitsTrustedWifi() {
        val s = com.zephyr.engine.Settings(trustedWifi = listOf("MyHomeSSID"), latencyTtlHours = 12)
        val text = LogsModel.diagnosticsSummary(
            "1.0 (1)", "Android 15", s,
            listOf(com.zephyr.engine.RecentErrors.Entry(0, com.zephyr.engine.ErrorCode.STORAGE_FULL)), java.util.TimeZone.getTimeZone("UTC"),
        )
        org.junit.Assert.assertFalse(text.contains("MyHomeSSID"))
        org.junit.Assert.assertFalse(text.contains("trustedWifi"))
        org.junit.Assert.assertTrue(text.contains("\"latencyTtlHours\":12"))
        org.junit.Assert.assertTrue(text.contains("1970-01-01 00:00:00.000 storage_full"))
    }
}
