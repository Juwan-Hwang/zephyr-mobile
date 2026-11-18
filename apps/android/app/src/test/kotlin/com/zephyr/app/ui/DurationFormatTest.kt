package com.zephyr.app.ui

import com.zephyr.design.format.ZFormat
import org.junit.Assert.assertEquals
import org.junit.Test

/** Audit #208 U20: the uptime always reads h:mm:ss, as in the prototype and on iOS. */
class DurationFormatTest {
    @Test fun underAnHourKeepsTheHour() {
        assertEquals("0:04:07", ZFormat.duration(247_000))
        assertEquals("0:00:00", ZFormat.duration(-5))
        assertEquals("2:14:07", ZFormat.duration(8_047_000))
        assertEquals("26:00:01", ZFormat.duration(93_601_000))
    }
}
