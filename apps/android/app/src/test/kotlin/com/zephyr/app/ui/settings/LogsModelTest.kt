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
}
