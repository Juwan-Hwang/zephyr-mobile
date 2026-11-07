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
    private var prober: kotlinx.coroutines.Job? = null
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
    private var tun: ParcelFileDescriptor? = null
    private var watcher: Job? = null
    private var bridge: TunBridge = TunBridge.Simulated
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
            bridge = TunBridge.pick(this@ZephyrVpnService, engine, s, engine.connectionState().first().mode)
            if (!bridge.createsTun && !com.zephyr.app.BuildConfig.DEBUG) {
                // Release never pretends: without a tunnel the app must not say "已连接" while traffic goes direct.
                fail(TunBridge.whyNoTunnel(engine)); return@launch
            }
            if (bridge.createsTun && tun == null) {
                tun = TunBridge.configure(Builder().setSession("Zephyr"), s.tun.mtu, s.tun.ipv6, s.tun.excludedApps, packageName).establish()
                val err = tun?.let { bridge.attach(it) } ?: "establish() returned null"
                if (err != null) {
                    android.util.Log.e("Zephyr", "core start failed: $err")
                    fail(com.zephyr.engine.ZephyrError(com.zephyr.engine.ErrorCode.CORE_CRASHED, err)); return@launch
                }
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
        (engine as? com.zephyr.engine.core.CoreEngine)?.let { core ->
            prober?.cancel()
            // Scene exits are probed once a minute while connected; core's failover tracker decides when to switch.
            prober = scope.launch { while (true) { kotlinx.coroutines.delay(PROBE_EVERY_MS); runCatching { core.probeScenes() } } }
        }
    }

    private suspend fun fail(e: com.zephyr.engine.ZephyrError) {
        stop()
        (engine as? com.zephyr.engine.core.CoreEngine)?.reportConnectFailure(e)
    }

    private suspend fun toggleMode() {
        val mode = engine.connectionState().first().mode
        engine.setMode(if (mode == com.zephyr.engine.ProxyMode.GLOBAL) com.zephyr.engine.ProxyMode.RULE else com.zephyr.engine.ProxyMode.GLOBAL)
    }

    private suspend fun stop() {
        prober?.cancel(); prober = null
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

    /** Low-memory signal: return Go heap to the OS before the LMK picks the VPN process. */
    override fun onTrimMemory(level: Int) {
        super.onTrimMemory(level)
        if (level >= TRIM_MEMORY_RUNNING_LOW) com.zephyr.engine.core.Mihomo.trimMemory()
    }

    override fun onDestroy() {
        scope.cancel()
        tun?.close()
        super.onDestroy()
    }

    private fun fgsType(): Int =
        if (Build.VERSION.SDK_INT >= 34) ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE else 0

    companion object {
        private const val PROBE_EVERY_MS = 60_000L
        const val ACTION_CONNECT = "com.zephyr.app.CONNECT"
        const val ACTION_DISCONNECT = "com.zephyr.app.DISCONNECT"
        const val ACTION_TOGGLE_MODE = "com.zephyr.app.TOGGLE_MODE"
    }
}
