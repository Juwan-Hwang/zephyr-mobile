package com.zephyr.app.di

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

/** Issue #208: an uncaught exception survives the process death and shows once in 日志. */
class CrashRecordTest {
    @get:Rule val tmp = TemporaryFolder()

    @Test fun writeThenTakeOnce() {
        val f = java.io.File(tmp.root, "sub/" + CrashRecord.FILE_NAME)
        val r = CrashRecord(f)
        r.write("main", IllegalStateException("Not allowed to start service", RuntimeException("inner")), 1234L)
        val line = r.takeLine()!!
        assertTrue(line, line.startsWith("previous run crashed: 1234 [main] java.lang.IllegalStateException: Not allowed to start service"))
        assertTrue(line, line.contains("caused by: java.lang.RuntimeException: inner"))
        assertTrue(line, line.contains("\n  at "))
        assertFalse(f.exists())
        assertNull(r.takeLine())
    }

    @Test fun noFileNoLine() = assertNull(CrashRecord(java.io.File(tmp.root, "none.txt")).takeLine())

    @Test fun framesCappedAndCauseLoopSafe() {
        val a = RuntimeException("a")
        val b = RuntimeException("b", a)
        a.initCause(b) // cycle
        val text = CrashRecord.format("t", b, 0)
        assertEquals(2, Regex("RuntimeException").findAll(text).count())
        val frames = text.lines().count { it.startsWith("  at ") }
        assertTrue("$frames", frames <= 2 * CrashRecord.MAX_FRAMES)
    }

    @Test fun installChainsToPreviousHandler() {
        val before = Thread.getDefaultUncaughtExceptionHandler()
        try {
            var chained: Throwable? = null
            Thread.setDefaultUncaughtExceptionHandler { _, e -> chained = e }
            val f = java.io.File(tmp.root, CrashRecord.FILE_NAME)
            CrashRecord.install(CrashRecord(f)) { 7L }
            val boom = IllegalStateException("boom")
            Thread.getDefaultUncaughtExceptionHandler()!!.uncaughtException(Thread.currentThread(), boom)
            assertTrue(chained === boom)
            assertTrue(f.readText().startsWith("7 ["))
        } finally {
            Thread.setDefaultUncaughtExceptionHandler(before)
        }
    }
}
