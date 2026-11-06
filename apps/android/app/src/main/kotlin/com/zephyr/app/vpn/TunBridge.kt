package com.zephyr.app.vpn

import android.net.VpnService
import android.os.ParcelFileDescriptor

/**
 * Hands the tun fd to the core. The core (mihomo embedded as a library via core-mobile) reads packets
 * from the fd directly — no Process(), no loopback socks hop.
 *
 * Until core-mobile exports `inject_tun_fd`, [Simulated] keeps the UI flow honest without establishing a tun:
 * establishing one with nobody reading it would black-hole the device's traffic.
 */
interface TunBridge {
    val createsTun: Boolean
    fun attach(fd: ParcelFileDescriptor)
    fun detach()

    object Simulated : TunBridge {
        override val createsTun = false
        override fun attach(fd: ParcelFileDescriptor) = Unit
        override fun detach() = Unit
    }

    companion object {
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
