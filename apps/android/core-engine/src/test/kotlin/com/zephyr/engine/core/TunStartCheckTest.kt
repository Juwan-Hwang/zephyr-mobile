package com.zephyr.engine.core

import org.junit.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue

/**
 * Issue #1 (S25 Ultra, Android 16 API 36, non-root, debug e244006): mihomo logged
 * `Start TUN listening error: build android rules: read packages list: open /data/system/packages.xml: permission denied`,
 * zm_start still returned success, and the app reported `core_crashed: libzmihomo missing`.
 */
class TunStartCheckTest {
    private val deviceError = "Start TUN listening error: build android rules: read packages list: open /data/system/packages.xml: permission denied"

    @Test fun successIsNotLibraryMissing() {
        // The regression: `lib?.run { take(zm_start(…)) } ?: "libzmihomo missing"` — null (started) became the error.
        assertNull(Mihomo.callResult(loaded = true) { null })
        assertEquals("zm_start: bad yaml", Mihomo.callResult(loaded = true) { "zm_start: bad yaml" })
        var called = false
        assertEquals(Mihomo.LIB_MISSING, Mihomo.callResult(loaded = false) { called = true; null })
        assertTrue(!called, "no call without the library")
    }

    @Test fun tunErrorFromTheDeviceLogIsTheReason() {
        val lines = listOf(
            "Load GeoSite rule: cn",
            "Initial configuration complete, total time: 43ms",
            "Mixed(http+socks) proxy listening at: 127.0.0.1:27927",
            "RESTful API unix listening at: /data/user/0/com.juwanh.zephyr/files/mihomo/ctl.sock",
            deviceError,
            "Mihomo shutting down",
        )
        val o = TunStartCheck.outcome(lines)
        assertEquals(TunStartCheck.Outcome.Failed("build android rules: read packages list: open /data/system/packages.xml: permission denied"), o)
        assertEquals(
            "tun start failed: build android rules: read packages list: open /data/system/packages.xml: permission denied",
            TunStartCheck.message(o as TunStartCheck.Outcome.Failed),
        )
    }

    @Test fun listeningAndUndecided() {
        assertEquals(TunStartCheck.Outcome.Listening, TunStartCheck.outcome(listOf("x", "[TUN] Tun adapter listening at: Meta(gvisor)")))
        assertNull(TunStartCheck.outcome(listOf("Load GeoSite rule: cn")))
        assertNull(TunStartCheck.outcome(emptyList()))
        // the first verdict wins
        assertEquals(TunStartCheck.Outcome.Listening, TunStartCheck.outcome(listOf("[TUN] Tun adapter listening at: x", deviceError)))
    }

    /** Shape core-mobile `runtime_config` emits (serde_yaml block style) for the device's settings. */
    private val deviceTun = """
        mixed-port: 27927
        tun:
          enable: true
          stack: gvisor
          file-descriptor: 42
          mtu: 9000
          inet6-address: null
          strict-route: true
          auto-route: false
          auto-detect-interface: false
          dns-hijack:
          - any:53
          - tcp://any:53
        dns:
          enable: true
          enhanced-mode: fake-ip
    """.trimIndent()

    @Test fun vpnServiceTunConfigPasses() {
        assertEquals(emptyList(), TunStartCheck.configProblems(deviceTun, fd = 42, mtu = 9000))
    }

    @Test fun packageFieldsRoutingAndFdAreFlagged() {
        val bad = deviceTun
            .replace("  auto-route: false", "  auto-route: true\n  include-package:\n  - com.android.chrome\n  exclude-package: []")
            .replace("file-descriptor: 42", "file-descriptor: 7")
        val p = TunStartCheck.configProblems(bad, fd = 42, mtu = 1500)
        assertTrue(p.any { "file-descriptor" in it }, "$p")
        assertTrue(p.any { "auto-route" in it }, "$p")
        assertTrue(p.any { "mtu" in it }, "$p")
        assertTrue("tun.include-package must not be set" in p, "$p")
        assertTrue("tun.exclude-package must not be set" in p, "$p")
        assertEquals(listOf("no tun block"), TunStartCheck.configProblems("mode: rule\n", 42, 9000))
    }

    @Test fun builderAndCoreGetTheSameMtu() {
        assertEquals(9000, CoreEngine.tunMtu(9000))
        assertEquals(9000, CoreEngine.tunMtu(65535))
        assertEquals(1280, CoreEngine.tunMtu(576))
    }
}
