package com.zephyr.app.vpn

import com.zephyr.engine.ErrorCode
import com.zephyr.engine.ZephyrError
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** Issue #1 (S25 Ultra, comment 7152702939): no endless relaunch-fail loops; first network snapshot is not "network back". */
class ReconnectBackoffTest {
    private val crash = ZephyrError(ErrorCode.CORE_CRASHED, "zm_start: listen tun: permission denied")
    private val geo = ZephyrError(ErrorCode.CORE_CRASHED, "geodata missing: GeoIP.dat")

    @Test fun coreCrashBacksOff30s2min10minThenPauses() {
        assertEquals(ReconnectBackoff.Outcome(disarm = false, retryInMs = 30_000L), ReconnectBackoff.onFailure(crash, 1))
        assertEquals(ReconnectBackoff.Outcome(disarm = false, retryInMs = 120_000L), ReconnectBackoff.onFailure(crash, 2))
        // third consecutive failure: on-demand paused until the user connects by hand
        assertEquals(ReconnectBackoff.Outcome(disarm = true, retryInMs = null), ReconnectBackoff.onFailure(crash, 3))
        assertEquals(ReconnectBackoff.Outcome(disarm = true, retryInMs = null), ReconnectBackoff.onFailure(crash, 7))
        assertEquals(600_000L, ReconnectBackoff.delayFor(3))
        assertEquals(30_000L, ReconnectBackoff.delayFor(0)) // clamped
    }

    @Test fun geodataMissingAndMissingSubscriptionPauseRightAway() {
        assertTrue(ReconnectBackoff.isGeodataMissing(geo))
        assertTrue(ReconnectBackoff.isGeodataMissing(ZephyrError(ErrorCode.CORE_CRASHED, "  Geodata missing: geosite.dat")))
        assertFalse(ReconnectBackoff.isGeodataMissing(crash))
        assertFalse(ReconnectBackoff.isGeodataMissing(ZephyrError(ErrorCode.INTERNAL, "geodata missing: x"))) // only core_crashed
        assertFalse(ReconnectBackoff.isGeodataMissing(null))
        assertEquals(ReconnectBackoff.Outcome(true, null), ReconnectBackoff.onFailure(geo, 1))
        assertEquals(ReconnectBackoff.Outcome(true, null), ReconnectBackoff.onFailure(ZephyrError(ErrorCode.SUBSCRIPTION_NOT_FOUND), 1))
        assertEquals(ReconnectBackoff.Outcome(true, null), ReconnectBackoff.onFailure(ZephyrError(ErrorCode.SUBSCRIPTION_INVALID), 1))
    }

    @Test fun otherErrorsKeepOnDemandArmedWithoutScheduledRetry() {
        val out = ReconnectBackoff.onFailure(ZephyrError(ErrorCode.NETWORK_UNAVAILABLE), 2)
        assertFalse(out.disarm); assertNull(out.retryInMs)
    }

    @Test fun automaticStartsWaitOutTheBackoffAndStopAfterThree() {
        assertEquals(0L, ReconnectBackoff.waitBeforeAuto(failures = 0, lastAttemptAt = 1_000L, now = 1_001L))
        assertEquals(0L, ReconnectBackoff.waitBeforeAuto(failures = 1, lastAttemptAt = 0L, now = 5L))
        // a sticky restart 10 s after a failed (or crashed) attempt waits the remaining 20 s
        assertEquals(20_000L, ReconnectBackoff.waitBeforeAuto(failures = 1, lastAttemptAt = 100_000L, now = 110_000L))
        assertEquals(0L, ReconnectBackoff.waitBeforeAuto(failures = 1, lastAttemptAt = 100_000L, now = 131_000L))
        assertEquals(60_000L, ReconnectBackoff.waitBeforeAuto(failures = 2, lastAttemptAt = 0L + 1, now = 60_001L))
        assertFalse(ReconnectBackoff.exhausted(2))
        assertTrue(ReconnectBackoff.exhausted(3))
    }

    @Test fun firstNetworkSnapshotOnlyRecords() {
        val up = NetworkReturn()
        assertFalse(up.update(true))  // cold start online: not "network back"
        assertFalse(up.update(true))
        assertFalse(up.update(false))
        assertTrue(up.update(true))   // none → some
        val offlineStart = NetworkReturn()
        assertFalse(offlineStart.update(false)) // first snapshot offline: records only
        assertTrue(offlineStart.update(true))
    }
}
