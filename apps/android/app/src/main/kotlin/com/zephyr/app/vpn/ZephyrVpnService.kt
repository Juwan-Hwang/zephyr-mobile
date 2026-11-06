package com.zephyr.app.vpn

import android.app.Notification
import android.content.Intent
import android.content.pm.ServiceInfo
import android.net.VpnService
import android.os.Build
import android.os.ParcelFileDescriptor
import androidx.core.app.NotificationManagerCompat
import androidx.core.app.ServiceCompat
import com.zephyr.app.di.AppGraph
import com.zephyr.app.tile.ZephyrTileService
import com.zephyr.app.widget.ZephyrWidget
import com.zephyr.engine.ConnectionStatus
import com.zephyr.engine.TrafficSample
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.onStart
import kotlinx.coroutines.launch

/**
 * Foreground VPN service: builds the tun, hands it to the core, keeps the ongoing notification fresh (1 Hz)
 * and mirrors state to the QS tile and widget.
 */
class ZephyrVpnService : VpnService() {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
    private var tun: ParcelFileDescriptor? = null
    private var watcher: Job? = null
    private val bridge: TunBridge = TunBridge.Simulated
    private val engine get() = AppGraph.engine

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_DISCONNECT -> { scope.launch { stop() }; return START_NOT_STICKY }
            ACTION_TOGGLE_MODE -> scope.launch { toggleMode() }
            else -> start()
        }
        return START_STICKY
    }

    private fun start() {
        val first = Notifications.ongoing(this, null, null, emptyList(), connecting = true)
        ServiceCompat.startForeground(this, Notifications.ID_ONGOING, first, fgsType())
        scope.launch {
            val s = engine.settings().first()
            if (bridge.createsTun && tun == null) {
                tun = TunBridge.configure(Builder().setSession("Zephyr"), s.tun.mtu, s.tun.ipv6, s.tun.excludedApps, packageName).establish()
                tun?.let(bridge::attach)
            }
            runCatching { engine.connect() }.onFailure { stop(); return@launch }
            watch()
        }
    }

    private fun watch() {
        watcher?.cancel()
        watcher = scope.launch {
            combine(
                engine.connectionState(),
                engine.traffic().onStart { emit(TrafficSample(0, 0, 0)) },
                engine.scenes(),
            ) { c, t, sc -> Triple(c, t, sc) }.collect { (c, t, sc) ->
                if (c.status == ConnectionStatus.DISCONNECTED) return@collect
                val n: Notification = Notifications.ongoing(this@ZephyrVpnService, c, t, sc, connecting = c.status == ConnectionStatus.CONNECTING)
                runCatching { NotificationManagerCompat.from(this@ZephyrVpnService).notify(Notifications.ID_ONGOING, n) }
            }
        }
        scope.launch { ZephyrTileService.requestRefresh(this@ZephyrVpnService); ZephyrWidget.refreshAll(this@ZephyrVpnService) }
    }

    private suspend fun toggleMode() {
        val mode = engine.connectionState().first().mode
        engine.setMode(if (mode == com.zephyr.engine.ProxyMode.GLOBAL) com.zephyr.engine.ProxyMode.RULE else com.zephyr.engine.ProxyMode.GLOBAL)
    }

    private suspend fun stop() {
        watcher?.cancel()
        runCatching { engine.disconnect() }
        bridge.detach()
        tun?.close(); tun = null
        ZephyrTileService.requestRefresh(this)
        ZephyrWidget.refreshAll(this)
        ServiceCompat.stopForeground(this, ServiceCompat.STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    override fun onRevoke() { scope.launch { stop() } }

    override fun onDestroy() {
        scope.cancel()
        tun?.close()
        super.onDestroy()
    }

    private fun fgsType(): Int =
        if (Build.VERSION.SDK_INT >= 34) ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE else 0

    companion object {
        const val ACTION_CONNECT = "com.zephyr.app.CONNECT"
        const val ACTION_DISCONNECT = "com.zephyr.app.DISCONNECT"
        const val ACTION_TOGGLE_MODE = "com.zephyr.app.TOGGLE_MODE"
    }
}
