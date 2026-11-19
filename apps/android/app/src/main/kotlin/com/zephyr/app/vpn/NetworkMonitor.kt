package com.zephyr.app.vpn

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.wifi.WifiInfo
import android.net.wifi.WifiManager
import android.os.Build
import com.zephyr.engine.NetworkInfo
import com.zephyr.engine.NetworkKind
import com.zephyr.engine.Settings
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/**
 * The app's own default network (Zephyr excludes itself from its tunnel, so this is the physical network the
 * VPN rides on). Feeds four things (release audit #208):
 * - E04 `setUnderlyingNetworks` — the VPN inherits the real network's metered/roaming flags;
 * - E23 「仅 Wi‑Fi 测速」 — automatic tests are skipped on a metered network;
 * - E01/U1 「受信任 Wi‑Fi」 — the SSID, when the OS shares it (needs location permission on Android 10+);
 * - E08 `ConnectionState.network` — real network info instead of the mock's「家」.
 *
 * Unknown is treated as unmetered / untrusted (same as iOS): a missing reading never blocks a test or drops
 * the tunnel.
 */
class NetworkMonitor(context: Context) {
    data class Snapshot(
        val network: Network?,
        val kind: NetworkKind,
        /** Unquoted SSID, or null when not on Wi‑Fi or the OS redacted it (no location permission / location off). */
        val ssid: String?,
        val metered: Boolean,
    )

    private val app = context.applicationContext
    private val cm = app.getSystemService(ConnectivityManager::class.java)
    private val _state = MutableStateFlow(Snapshot(null, NetworkKind.OTHER, null, metered = false))
    val state: StateFlow<Snapshot> = _state.asStateFlow()
    private var callback: ConnectivityManager.NetworkCallback? = null

    fun start() {
        if (callback != null || cm == null) return
        val cb = if (Build.VERSION.SDK_INT >= 31) {
            // FLAG_INCLUDE_LOCATION_INFO: without it the WifiInfo in the capabilities never carries the SSID.
            object : ConnectivityManager.NetworkCallback(FLAG_INCLUDE_LOCATION_INFO) {
                override fun onCapabilitiesChanged(network: Network, caps: NetworkCapabilities) = publish(network, caps)
                override fun onLost(network: Network) = lost(network)
            }
        } else {
            object : ConnectivityManager.NetworkCallback() {
                override fun onCapabilitiesChanged(network: Network, caps: NetworkCapabilities) = publish(network, caps)
                override fun onLost(network: Network) = lost(network)
            }
        }
        runCatching { cm.registerDefaultNetworkCallback(cb) }.onSuccess { callback = cb }
    }

    /** Re-reads the SSID after the user grants location permission (the OS does not resend capabilities for it). */
    fun refresh() {
        val cb = callback ?: return start()
        runCatching { cm?.unregisterNetworkCallback(cb) }
        callback = null
        start()
    }

    private fun publish(network: Network, caps: NetworkCapabilities) {
        val wifi = caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI)
        val kind = when {
            wifi -> NetworkKind.WIFI
            caps.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) -> NetworkKind.CELLULAR
            caps.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET) -> NetworkKind.ETHERNET
            else -> NetworkKind.OTHER
        }
        val ssid = if (wifi) readSsid(caps) else null
        _state.value = Snapshot(network, kind, ssid, metered = isMetered(caps))
    }

    private fun lost(network: Network) {
        if (_state.value.network == network) _state.value = Snapshot(null, NetworkKind.OTHER, null, metered = false)
    }

    private fun readSsid(caps: NetworkCapabilities): String? {
        if (!hasLocationPermission(app)) return null
        val fromCaps = if (Build.VERSION.SDK_INT >= 29) (caps.transportInfo as? WifiInfo)?.ssid else null
        val raw = cleanSsid(fromCaps) ?: if (Build.VERSION.SDK_INT < 31) {
            // API 28–30: the capabilities' WifiInfo is redacted; WifiManager still answers (ACCESS_WIFI_STATE + location).
            @Suppress("DEPRECATION")
            runCatching { app.getSystemService(WifiManager::class.java)?.connectionInfo?.ssid }.getOrNull()
        } else null
        return cleanSsid(raw)
    }

    companion object {
        private fun isMetered(caps: NetworkCapabilities): Boolean {
            if (caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_NOT_METERED)) return false
            if (Build.VERSION.SDK_INT >= 30 && caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_TEMPORARILY_NOT_METERED)) return false
            return true
        }

        /** Location (fine) is what Android 10+ requires before it reveals the SSID of the current Wi‑Fi. */
        fun hasLocationPermission(ctx: Context): Boolean =
            ctx.checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED

        /** System location switch (API 28+). Android 10+ also hides the SSID while it is off, even with permission. */
        fun locationEnabled(ctx: Context): Boolean =
            runCatching { ctx.getSystemService(android.location.LocationManager::class.java)?.isLocationEnabled ?: true }.getOrDefault(true)

        /** `"Home"` → `Home`; the OS placeholder `<unknown ssid>` and blanks → null. */
        fun cleanSsid(raw: String?): String? {
            val s = raw?.trim() ?: return null
            if (s.isEmpty() || s == WifiManager.UNKNOWN_SSID || s == "<unknown ssid>") return null
            val unq = if (s.length >= 2 && s.startsWith('"') && s.endsWith('"')) s.substring(1, s.length - 1) else s
            return unq.takeIf { it.isNotBlank() }
        }

        /** Whether [ssid] is one of the user's trusted networks (trimmed, case-sensitive like iOS NEOnDemandRule). */
        fun isTrusted(settings: Settings, ssid: String?): Boolean {
            if (ssid == null) return false
            return settings.trustedWifi.any { it.trim().isNotEmpty() && it.trim() == ssid }
        }

        /**
         * 「受信任时断开」: drop the tunnel when the device *moves onto* a trusted Wi‑Fi while connected. Only a
         * transition counts, so connecting by hand while already on that network is respected (Android has no
         * system on-demand to fight the user like iOS does, see audit E02).
         */
        fun shouldDisconnect(settings: Settings, previousSsid: String?, ssid: String?): Boolean =
            settings.disconnectOnTrusted && ssid != null && ssid != previousSsid && isTrusted(settings, ssid)

        /**
         * Contract §16.a③: what counts as "the default underlying network changed" — Wi‑Fi ↔ cellular, or another
         * SSID. When the SSID is unknown the network handle stands in (a Wi‑Fi reconnect then also counts, which only
         * costs an extra closeAll). No network → null: losing the network is not a switch; the next one decides.
         */
        data class ChangeKey(val kind: NetworkKind, val ident: Any)

        fun changeKey(hasNetwork: Boolean, kind: NetworkKind, ssid: String?, network: Any?): ChangeKey? =
            if (!hasNetwork || network == null) null else ChangeKey(kind, ssid ?: network)

        fun changeKey(s: Snapshot): ChangeKey? = changeKey(s.network != null, s.kind, s.ssid, s.network)

        /** 「仅 Wi‑Fi 测速」: automatic tests run unless the setting is on and the network is metered. */
        fun autoTestAllowed(wifiOnly: Boolean, metered: Boolean): Boolean = !(wifiOnly && metered)

        fun info(s: Snapshot, settings: Settings): NetworkInfo? =
            if (s.network == null) null else NetworkInfo(s.kind, s.ssid, trusted = isTrusted(settings, s.ssid))
    }
}
