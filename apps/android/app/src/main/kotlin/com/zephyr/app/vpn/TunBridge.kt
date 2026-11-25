package com.zephyr.app.vpn

import android.content.Context
import android.net.VpnService
import android.os.ParcelFileDescriptor
import com.zephyr.engine.ErrorCode
import com.zephyr.engine.ProxyMode
import com.zephyr.engine.ZephyrError
import com.zephyr.engine.ZephyrException
import com.zephyr.engine.Settings
import com.zephyr.engine.ZephyrEngine
import com.zephyr.engine.core.CoreEngine
import com.zephyr.engine.core.Mihomo
import com.zephyr.engine.core.TunStartCheck
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
    /**
     * Null on success, else why (typed, issue #1): `subscription_not_found` when there is nothing to run, the
     * engine's own code when the runtime config fails, `core_crashed` only for the kernel itself.
     */
    suspend fun attach(fd: ParcelFileDescriptor): ZephyrError?
    /**
     * Issue #1: what can be checked before `establish()` (library loaded, runtime config builds). Null = go ahead,
     * else the reason; the service fails without ever creating the tun.
     */
    suspend fun preflight(): ZephyrError? = null
    fun detach()

    /** No core packaged or no subscription yet: UI flow works, no tun is created (an unread tun would black-hole traffic). */
    object Simulated : TunBridge {
        override val createsTun = false
        override suspend fun attach(fd: ParcelFileDescriptor): ZephyrError? = null
        override fun detach() = Unit
    }

    /**
     * Real path: core-mobile `runtimeConfig` (active subscription + Zephyr settings + tun fd, control plane on
     * a private unix socket) → `zm_start`. mihomo reads packets straight from the fd.
     */
    class Embedded(private val ctx: Context, private val engine: CoreEngine, private val settings: Settings, private val mode: ProxyMode) : TunBridge {
        override val createsTun = true
        override suspend fun attach(fd: ParcelFileDescriptor): ZephyrError? {
            val sock = controllerSocket(ctx)
            engine.tunnelStarting = true // §16.b ③: changes from here on are queued, applied once after start
            try { return start(fd, sock) } finally { engine.tunnelStarting = false }
        }

        override suspend fun preflight(): ZephyrError? {
            if (!Mihomo.available) return kernelError("libzmihomo missing")
            prepareGeodata()
            // Same config as attach() minus the fd: catches "no active subscription" and config errors up front.
            return configCheck { engine.runtimeConfig(null, controllerSocket(ctx).path, settings, mode) }
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

        private suspend fun start(fd: ParcelFileDescriptor, sock: File): ZephyrError? {
            var cfg: String? = null
            configCheck { engine.runtimeConfig(fd.fd, sock.path, settings, mode).also { cfg = it } }?.let { return it }
            val config = cfg!!
            // Issue #1: the tun block must be the VpnService one (system fd, mihomo does not route, no per-app fields).
            TunStartCheck.configProblems(config, fd.fd, tunMtu(settings.tun.mtu)).takeIf { it.isNotEmpty() }?.let {
                android.util.Log.w("Zephyr", "tun config: ${it.joinToString("; ")}")
                engine.appLog(com.zephyr.engine.LogLevel.WARNING, "tun config: ${it.joinToString("; ")}")
            }
            Mihomo.setMemoryLimit(MEMORY_LIMIT)
            sock.delete() // stale socket from a crashed run would make the listener fail
            val since = withContext(Dispatchers.IO) { Mihomo.logSeq() }
            val err = withContext(Dispatchers.IO) { Mihomo.start(sock.parentFile!!.path, config, sock.path) }
                // Issue #1: zm_start returns success even when the TUN listener failed (mihomo only logs it); without
                // this the tun fd is never read and every app's traffic goes nowhere. Stop and report the real reason.
                ?: Mihomo.tunStartError(since)?.also { withContext(Dispatchers.IO) { Mihomo.stop() } }
            if (err == null) engine.tunnelStarted() // usage ledger: a fresh core counts from zero (audit E39)
            if (err == null) engine.reloader = {
                // Scene/exception/override changes that need new groups or rules: same fd, fresh config.
                val s = engine.settings().first(); val m = engine.connectionState().first().mode
                reloadWith(engine.runtimeConfig(fd.fd, sock.path, s, m)) { withContext(Dispatchers.IO) { Mihomo.reload(it) } }
            }
            // §16.b③ 连接中: settings changed while connecting (e.g. 本地代理 port / 需要密码) are applied once, right after start.
            if (err == null) {
                engine.tunnelStarting = false
                engine.flushPendingReload(force = CoreEngine.affectsRuntime(settings, engine.settings().first()))
            }
            return err?.let { kernelError(it) }
        }
        override fun detach() { engine.reloader = null; Mihomo.stop(); Mihomo.trimMemory() }
    }

    companion object {
        /** Go soft limit for the VPN process (spec: core ≤ 60 MB RSS steady state on Android). */
        const val MEMORY_LIMIT = 48L * 1024 * 1024
        const val MTU_MIN = 1280
        const val MTU_MAX = 9000
        const val NO_ACTIVE_SUBSCRIPTION = "no active subscription"

        /** Nothing to run: on-demand pauses, no backoff (ReconnectBackoff); Home says 「先添加一个订阅」. */
        fun noSubscription(): ZephyrError = ZephyrError(ErrorCode.SUBSCRIPTION_NOT_FOUND, NO_ACTIVE_SUBSCRIPTION)

        /** The kernel itself (library, `zm_start`): the only `core_crashed` this bridge reports. */
        fun kernelError(message: String): ZephyrError = ZephyrError(ErrorCode.CORE_CRASHED, message)

        /**
         * Issue #1 (real device, main 10bd48f): a config that builds is success. The previous
         * `runtimeConfig(...)?.let { null } ?: "no active subscription"` turned every successful build into that error,
         * so every real-device connect failed as `core_crashed` and entered the backoff loop.
         * null config → [noSubscription]; a thrown [ZephyrException] keeps its code; anything else is `core_crashed`.
         */
        suspend fun configCheck(build: suspend () -> String?): ZephyrError? = try {
            if (build() != null) null else noSubscription()
        } catch (e: ZephyrException) { e.error } catch (e: kotlinx.coroutines.CancellationException) { throw e } catch (t: Throwable) {
            kernelError(t.message ?: "runtime config failed")
        }

        /** Hot reload: null config → [NO_ACTIVE_SUBSCRIPTION]; else whatever `zm_reload` says (null = applied). */
        suspend fun reloadWith(cfg: String?, reload: suspend (String) -> String?): String? =
            if (cfg == null) NO_ACTIVE_SUBSCRIPTION else reload(cfg)

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
                    kernelError("native core not packaged")
                else -> noSubscription()
            }
        }

        /** mihomo home dir holds the socket; same path for zm_start and the REST client (RustLive). */
        fun controllerSocket(ctx: Context): File = File(File(ctx.filesDir, "mihomo").apply { mkdirs() }, "ctl.sock")

        /** One MTU for `VpnService.Builder.setMtu` and the mihomo tun block. */
        fun tunMtu(mtu: Int): Int = CoreEngine.tunMtu(mtu)

        /** Tun parameters shared with core config (fake-ip range 198.18.0.0/15, like desktop TUN). */
        fun configure(b: VpnService.Builder, mtu: Int, ipv6: Boolean, excluded: List<String>, self: String): VpnService.Builder = b.apply {
            // Audit E16: same clamp as iOS TunnelConfiguration (settings already reject < 1280 / > 9000); the mihomo tun
            // block gets the same value (CoreEngine.runtimeConfig uses [tunMtu] too).
            setMtu(tunMtu(mtu))
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
