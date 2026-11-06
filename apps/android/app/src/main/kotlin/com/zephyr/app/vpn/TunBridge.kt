package com.zephyr.app.vpn

import android.content.Context
import android.net.VpnService
import android.os.ParcelFileDescriptor
import com.zephyr.engine.core.Mihomo
import java.io.File

/**
 * Hands the tun fd to the core. The core (mihomo embedded as a library via mihomo-mobile) reads packets from
 * the fd directly — no child process, no loopback socks hop.
 */
interface TunBridge {
    /** True when this bridge will actually carry traffic (and therefore wants a real tun). */
    val createsTun: Boolean
    /** Returns null on success or an error message. */
    fun attach(fd: ParcelFileDescriptor): String?
    fun detach()

    /** No core packaged or no profile yet: UI flow works, no tun is created (an unread tun would black-hole traffic). */
    object Simulated : TunBridge {
        override val createsTun = false
        override fun attach(fd: ParcelFileDescriptor): String? = null
        override fun detach() = Unit
    }

    /** Real path: profile YAML → zephyr-core `injectTunFd` (tun.file-descriptor) → `zm_start`. */
    class Embedded(private val ctx: Context, private val profile: File) : TunBridge {
        override val createsTun = true
        override fun attach(fd: ParcelFileDescriptor): String? {
            val home = File(ctx.filesDir, "mihomo").apply { mkdirs() }
            val cfg = try { uniffi.zephyr_core.injectTunFd(profile.readText(), fd.fd) } catch (t: Throwable) { return t.message ?: "inject_tun_fd failed" }
            Mihomo.setMemoryLimit(MEMORY_LIMIT)
            return Mihomo.start(home.path, cfg, File(home, "ctl.sock").path)
        }
        override fun detach() { Mihomo.stop(); Mihomo.trimMemory() }
    }

    companion object {
        /** Go soft limit for the VPN process (spec: core ≤ 60 MB RSS steady state on Android). */
        const val MEMORY_LIMIT = 48L * 1024 * 1024

        fun pick(ctx: Context): TunBridge {
            val profile = File(ctx.filesDir, "profiles/active.yaml")
            return if (Mihomo.available && profile.isFile) Embedded(ctx, profile) else Simulated
        }

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
