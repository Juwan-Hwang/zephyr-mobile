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
            val cfg = try {
                engine.runtimeConfig(fd.fd, sock.path, settings, mode) ?: return "no active subscription"
            } catch (t: Throwable) { return t.message ?: "runtime config failed" }
            Mihomo.setMemoryLimit(MEMORY_LIMIT)
            sock.delete() // stale socket from a crashed run would make the listener fail
            return withContext(Dispatchers.IO) { Mihomo.start(sock.parentFile!!.path, cfg, sock.path) }
        }
        override fun detach() { Mihomo.stop(); Mihomo.trimMemory() }
    }

    companion object {
        /** Go soft limit for the VPN process (spec: core ≤ 60 MB RSS steady state on Android). */
        const val MEMORY_LIMIT = 48L * 1024 * 1024

        fun pick(ctx: Context, engine: ZephyrEngine, settings: Settings, mode: ProxyMode): TunBridge {
            val core = engine as? CoreEngine
            val ready = Mihomo.available && core != null && core.isNative && core.activeSubscription() != null
            return if (ready) Embedded(ctx, core!!, settings, mode) else Simulated
        }

        /** mihomo home dir holds the socket; same path for zm_start and the REST client (RustLive). */
        fun controllerSocket(ctx: Context): File = File(File(ctx.filesDir, "mihomo").apply { mkdirs() }, "ctl.sock")

        /** Tun parameters shared with core config (fake-ip range 198.18.0.0/15, like desktop TUN). */
        fun configure(b: VpnService.Builder, mtu: Int, ipv6: Boolean, excluded: List<String>, self: String): VpnService.Builder = b.apply {
            setMtu(mtu)
            addAddress("198.18.0.1", 30)
            addRoute("0.0.0.0", 0)
            addDnsServer("198.18.0.2")
            if (ipv6) { addAddress("fdfe:dcba:9876::1", 126); addRoute("::", 0) }
            setBlocking(false)
            setMetered(false)
            runCatching { addDisallowedApplication(self) }
            excluded.forEach { runCatching { addDisallowedApplication(it) } }
        }
    }
}
