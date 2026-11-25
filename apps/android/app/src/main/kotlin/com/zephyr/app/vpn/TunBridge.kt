package com.zephyr.app.vpn

import android.content.Context
import android.net.VpnService
import android.os.ParcelFileDescriptor
import com.zephyr.engine.ProxyMode
import com.zephyr.engine.Settings
import com.zephyr.engine.ZephyrEngine
import com.zephyr.engine.core.CoreEngine
import com.zephyr.engine.core.Mihomo
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.coroutines.flow.first
import java.io.File

/**
 * Hands the tun fd to the core. The core (mihomo embedded as a library via mihomo-mobile) reads packets from
 * the fd directly — no child process, no loopback socks hop.
 */
interface TunBridge {
    /** True when this bridge will actually carry traffic (and therefore wants a real tun). */
    val createsTun: Boolean
    /** Returns null on success or an error message. */
    suspend fun attach(fd: ParcelFileDescriptor): String?
    /**
     * Issue #1: what can be checked before `establish()` (library loaded, runtime config builds). Null = go ahead,
     * else the reason; the service fails without ever creating the tun.
     */
    suspend fun preflight(): String? = null
    fun detach()

    /** No core packaged or no subscription yet: UI flow works, no tun is created (an unread tun would black-hole traffic). */
    object Simulated : TunBridge {
        override val createsTun = false
        override suspend fun attach(fd: ParcelFileDescriptor): String? = null
        override fun detach() = Unit
    }

    /**
     * Real path: core-mobile `runtimeConfig` (active subscription + Zephyr settings + tun fd, control plane on
     * a private unix socket) → `zm_start`. mihomo reads packets straight from the fd.
     */
    class Embedded(private val ctx: Context, private val engine: CoreEngine, private val settings: Settings, private val mode: ProxyMode) : TunBridge {
        override val createsTun = true
        override suspend fun attach(fd: ParcelFileDescriptor): String? {
            val sock = controllerSocket(ctx)
            engine.tunnelStarting = true // §16.b ③: changes from here on are queued, applied once after start
            try { return start(fd, sock) } finally { engine.tunnelStarting = false }
        }

        override suspend fun preflight(): String? {
            if (!Mihomo.available) return "libzmihomo missing"
            prepareGeodata()
            return try {
                // Same config as attach() minus the fd: catches "no active subscription" and config errors up front.
                engine.runtimeConfig(null, controllerSocket(ctx).path, settings, mode)?.let { null } ?: "no active subscription"
            } catch (t: Throwable) { t.message ?: "runtime config failed" }
        }

        /**
         * Contract §20.d / docs/geodata.md, before every `zm_start`: copy the APK's bundled snapshot into the mihomo
         * home when absent, then `seedKernelGeodata` (core's own geo/ files). With the whole snapshot in place mihomo
         * is told not to download at all (timeout 0); otherwise the bounded default (15 s) stays. Nothing here fails the
         * start: if a file is still missing, `zm_start` returns `geodata missing:` and ReconnectBackoff / HomeHeader handle it.
         */
        private suspend fun prepareGeodata() {
            val home = controllerSocket(ctx).parentFile!!
            val bundled = BundledGeodata.bundled(ctx)
            withContext(Dispatchers.IO) {
                BundledGeodata.install(ctx, home).takeIf { it.isNotEmpty() }?.let { android.util.Log.i("Zephyr", "geodata installed: $it") }
            }
            runCatching { engine.seedKernelGeodata(home.path) }
                .onSuccess { if (it.isNotEmpty()) android.util.Log.i("Zephyr", "geodata seeded: $it") }
                .onFailure { android.util.Log.w("Zephyr", "seedKernelGeodata failed: ${it.message}") }
            Mihomo.setGeodataTimeout(if (BundledGeodata.allPresent(bundled, home)) 0L else -1L)
        }

        private suspend fun start(fd: ParcelFileDescriptor, sock: File): String? {
            val cfg = try {
                engine.runtimeConfig(fd.fd, sock.path, settings, mode) ?: return "no active subscription"
            } catch (t: Throwable) { return t.message ?: "runtime config failed" }
            Mihomo.setMemoryLimit(MEMORY_LIMIT)
            sock.delete() // stale socket from a crashed run would make the listener fail
            val err = withContext(Dispatchers.IO) { Mihomo.start(sock.parentFile!!.path, cfg, sock.path) }
            if (err == null) engine.tunnelStarted() // usage ledger: a fresh core counts from zero (audit E39)
            if (err == null) engine.reloader = {
                // Scene/exception/override changes that need new groups or rules: same fd, fresh config.
                val s = engine.settings().first(); val m = engine.connectionState().first().mode
                engine.runtimeConfig(fd.fd, sock.path, s, m)?.let { withContext(Dispatchers.IO) { Mihomo.reload(it) } } ?: "no active subscription"
            }
            // §16.b③ 连接中: settings changed while connecting (e.g. 本地代理 port / 需要密码) are applied once, right after start.
            if (err == null) {
                engine.tunnelStarting = false
                engine.flushPendingReload(force = CoreEngine.affectsRuntime(settings, engine.settings().first()))
            }
            return err
        }
        override fun detach() { engine.reloader = null; Mihomo.stop(); Mihomo.trimMemory() }
    }

    companion object {
        /** Go soft limit for the VPN process (spec: core ≤ 60 MB RSS steady state on Android). */
        const val MEMORY_LIMIT = 48L * 1024 * 1024
        const val MTU_MIN = 1280
        const val MTU_MAX = 9000

        suspend fun pick(ctx: Context, engine: ZephyrEngine, settings: Settings, mode: ProxyMode): TunBridge {
            val core = engine as? CoreEngine
            val ready = Mihomo.available && core != null && core.isNative && core.activeSubscription() != null
            return if (ready) Embedded(ctx, core!!, settings, mode) else Simulated
        }

        /** Why [pick] fell back to [Simulated]; shown as the failure reason. */
        suspend fun whyNoTunnel(engine: ZephyrEngine): com.zephyr.engine.ZephyrError {
            val core = engine as? CoreEngine
            return when {
                !Mihomo.available || core == null || !core.isNative ->
                    com.zephyr.engine.ZephyrError(com.zephyr.engine.ErrorCode.CORE_CRASHED, "native core not packaged")
                else -> com.zephyr.engine.ZephyrError(com.zephyr.engine.ErrorCode.SUBSCRIPTION_NOT_FOUND, "no active subscription")
            }
        }

        /** mihomo home dir holds the socket; same path for zm_start and the REST client (RustLive). */
        fun controllerSocket(ctx: Context): File = File(File(ctx.filesDir, "mihomo").apply { mkdirs() }, "ctl.sock")

        /** Tun parameters shared with core config (fake-ip range 198.18.0.0/15, like desktop TUN). */
        fun configure(b: VpnService.Builder, mtu: Int, ipv6: Boolean, excluded: List<String>, self: String): VpnService.Builder = b.apply {
            // Audit E16: same clamp as iOS TunnelConfiguration (settings already reject < 576 / > 9000).
            setMtu(mtu.coerceIn(MTU_MIN, MTU_MAX))
            addAddress("198.18.0.1", 30)
            addDnsServer("198.18.0.2")
            if (ipv6) addAddress("fdfe:dcba:9876::1", 126)
            // Contract §16.a①: default routes minus the LAN set (excludeRoute on 33+, complement table below).
            LanBypass.apply(this, ipv6)
            setBlocking(false)
            // Audit E04: no setMetered(false). The VPN stays "metered if its underlying network is", and the service
            // keeps setUnderlyingNetworks pointed at the real network, so apps (and WorkManager's UNMETERED) see
            // cellular as metered.
            runCatching { addDisallowedApplication(self) }
            excluded.forEach { runCatching { addDisallowedApplication(it) } }
        }
    }
}
