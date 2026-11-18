package com.zephyr.engine.core

import com.zephyr.engine.LogLevel
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.File
import java.time.ZoneId

class UsageLedgerTest {
    @get:Rule val tmp = TemporaryFolder()
    private val zone = ZoneId.of("Asia/Shanghai")
    private val t0 = 1_793_929_260_000L // 2026-11-06 09:41 CST

    @Test fun countsDeltasIntoHourAndHandlesRestart() {
        val f = File(tmp.root, "usage.json")
        val l = UsageLedger(f) { zone }
        l.record(1_000, t0)            // first sample of a fresh core: all of it is today's traffic
        l.record(3_000, t0 + 1_000)    // +2000
        l.record(500, t0 + 2_000)      // counter went back: core restarted, the new reading counts (audit E39)
        l.record(1_500, t0 + 3_000)    // +1000
        val s = l.today(t0 + 3_000)
        assertEquals(4_500L, s.hourly[9])
        assertEquals(3_000L, s.onlineMs)
        l.save(t0 + 3_000)
        assertEquals(4_500L, UsageLedger(f) { zone }.today(t0 + 3_000).hourly.sum())
    }

    @Test fun tunnelStartDropsStaleBaseline() {
        val f = File(tmp.root, "usage.json")
        val l = UsageLedger(f) { zone }
        l.record(0, t0); l.record(10_000, t0 + 1_000); l.save(t0 + 1_000)
        // New process, new core: its first reading (12 000) is above the stale saved total but is all new traffic.
        val next = UsageLedger(f) { zone }
        next.tunnelStarted()
        next.record(12_000, t0 + 60_000)
        assertEquals(22_000L, next.today(t0 + 60_000).hourly.sum())
        assertEquals(1_000L, next.today(t0 + 60_000).onlineMs) // the gap across the restart is not online time
    }

    @Test fun newDayStartsFromZero() {
        val l = UsageLedger(null) { zone }
        l.record(0, t0); l.record(5_000, t0 + 1_000)
        assertEquals(5_000L, l.today(t0 + 1_000).hourly.sum())
        val tomorrow = t0 + 86_400_000L
        assertEquals(0L, l.today(tomorrow).hourly.sum())
        l.record(6_000, tomorrow)
        assertEquals(1_000L, l.today(tomorrow).hourly.sum())
    }

    @Test fun parsesZmLogs() {
        val r = LogsJson.parse("""{"seq":7,"lines":[{"seq":6,"level":"warning","msg":"dial failed","at":5},{"seq":7,"level":"info","msg":"ok","at":6}]}""")
        assertEquals(7L, r.seq)
        assertEquals(LogLevel.WARNING, r.lines[0].level)
        assertEquals("ok", r.lines[1].message)
        assertEquals(0, LogsJson.parse("garbage").lines.size)
    }
}
