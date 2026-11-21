package com.zephyr.app.screenshot

import org.junit.rules.ExternalResource
import java.util.TimeZone

/**
 * Pins the JVM default time zone for screenshot tests. The tests already pin "now" ([HomeScreenshotTest.NOW]) and
 * MockEngine's clock, but calendar-day copy ("周一到期", "26 天后到期", the ≤ 7-day amber rule, log timestamps) is
 * computed in `ZoneId.systemDefault()`, so a baseline recorded on a machine west of UTC would read "周日到期".
 * UTC is what the CI runner (record_android_snapshots / verifyPaparazziDebug) uses, so pinning it keeps every
 * existing baseline valid and makes local runs agree with CI.
 */
class FixedZoneRule(private val zone: String = "UTC") : ExternalResource() {
    private var previous: TimeZone? = null
    override fun before() {
        previous = TimeZone.getDefault()
        TimeZone.setDefault(TimeZone.getTimeZone(zone))
    }
    override fun after() {
        previous?.let(TimeZone::setDefault)
    }
}
