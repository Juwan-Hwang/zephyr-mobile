package com.zephyr.app.vpn

import com.zephyr.engine.ErrorCode
import com.zephyr.engine.ZephyrError
import com.zephyr.engine.ZephyrException
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Issue #1 (real device, debug APK from main 10bd48f): 「连接失败 / 内核未能启动」 + `connect failed [core_crashed]:
 * no active subscription`, then on-demand backoff 30 s → 2 min, with a subscription imported in onboarding.
 */
class TunBridgeErrorsTest {
    @Test fun configThatBuildsIsSuccess() = runBlocking {
        // The regression: `runtimeConfig(...)?.let { null } ?: "no active subscription"` failed every successful build.
        assertNull(TunBridge.configCheck { "mode: rule\ntun: {enable: true}" })
    }

    @Test fun noConfigIsSubscriptionNotFoundNotCoreCrashed() = runBlocking {
        val e = TunBridge.configCheck { null }!!
        assertEquals(ErrorCode.SUBSCRIPTION_NOT_FOUND, e.code)
        assertEquals(TunBridge.NO_ACTIVE_SUBSCRIPTION, e.message)
        assertEquals(ErrorCode.SUBSCRIPTION_NOT_FOUND, TunBridge.noSubscription().code)
    }

    @Test fun engineErrorsKeepTheirCodeOthersAreKernel() = runBlocking {
        val inv = TunBridge.configCheck { throw ZephyrException(ErrorCode.SUBSCRIPTION_INVALID, "bad yaml") }!!
        assertEquals(ErrorCode.SUBSCRIPTION_INVALID, inv.code)
        val io = TunBridge.configCheck { throw IllegalStateException("boom") }!!
        assertEquals(ErrorCode.CORE_CRASHED, io.code); assertEquals("boom", io.message)
    }

    @Test fun kernelGeodataErrorStaysCoreCrashedWithPrefix() {
        val e = TunBridge.kernelError("geodata missing: GeoIP.dat")
        assertEquals(ErrorCode.CORE_CRASHED, e.code)
        assertTrue(ReconnectBackoff.isGeodataMissing(e))
    }

    @Test fun noSubscriptionPausesOnDemandWithoutBackoff() {
        for (streak in 1..3) {
            val out = ReconnectBackoff.onFailure(TunBridge.noSubscription(), streak)
            assertTrue(out.disarm); assertNull(out.retryInMs)
        }
        // whereas a real kernel failure still backs off
        assertEquals(30_000L, ReconnectBackoff.onFailure(TunBridge.kernelError("zm_start: x"), 1).retryInMs)
        assertFalse(ReconnectBackoff.onFailure(TunBridge.kernelError("zm_start: x"), 1).disarm)
    }

    @Test fun reloadSuccessIsNotAnError() = runBlocking {
        // Same inversion on the hot-reload path: zm_reload's null (applied) became "no active subscription".
        assertNull(TunBridge.reloadWith("cfg") { null })
        assertEquals("zm_reload: bad", TunBridge.reloadWith("cfg") { "zm_reload: bad" })
        assertEquals(TunBridge.NO_ACTIVE_SUBSCRIPTION, TunBridge.reloadWith(null) { error("not called") })
    }

    @Test fun homeSaysAddASubscription() {
        assertEquals(com.zephyr.app.R.string.home_failure_no_subscription, com.zephyr.app.ui.home.failureText(TunBridge.noSubscription()))
        assertEquals(com.zephyr.app.R.string.home_failure_core, com.zephyr.app.ui.home.failureText(ZephyrError(ErrorCode.CORE_CRASHED, "zm_start: x")))
    }
}
