package com.zephyr.app.tile

import android.content.ComponentName
import android.content.Context
import android.graphics.drawable.Icon
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService
import com.zephyr.app.R
import com.zephyr.app.di.AppGraph
import com.zephyr.engine.ConnectionStatus
import com.zephyr.engine.ProxyMode
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.launch

/** Quick Settings tile: "Zephyr / 规则 · 东京 03" (prototype `and`). Tap toggles; long-press opens the app. */
class ZephyrTileService : TileService() {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private var job: Job? = null

    override fun onStartListening() {
        AppGraph.init(this)
        job = scope.launch {
            combine(AppGraph.engine.connectionState(), AppGraph.engine.scenes()) { c, s -> c to s }.collect { (c, scenes) ->
                val tile = qsTile ?: return@collect
                val on = c.status == ConnectionStatus.CONNECTED || c.status == ConnectionStatus.CONNECTING
                tile.state = if (on) Tile.STATE_ACTIVE else Tile.STATE_INACTIVE
                tile.label = getString(R.string.app_name)
                tile.icon = Icon.createWithResource(this@ZephyrTileService, R.drawable.ic_stat_zephyr)
                val mode = when (c.mode) { ProxyMode.RULE -> "规则"; ProxyMode.GLOBAL -> "全局"; ProxyMode.DIRECT -> "直连" }
                val node = scenes.firstOrNull()?.selected?.name
                tile.subtitle = when (c.status) {
                    ConnectionStatus.CONNECTING -> "正在连接…"
                    ConnectionStatus.CONNECTED -> listOfNotNull(mode, node).joinToString(" · ")
                    else -> getString(R.string.tile_off)
                }
                tile.updateTile()
            }
        }
    }

    override fun onStopListening() { job?.cancel(); job = null }

    override fun onClick() {
        AppGraph.init(this)
        if (AppGraph.connection.permissionIntent() != null) {
            // Needs an Activity to grant VPN permission.
            val pi = android.app.PendingIntent.getActivity(
                this, 0,
                android.content.Intent(this, com.zephyr.app.MainActivity::class.java).setAction(com.zephyr.app.MainActivity.ACTION_CONNECT),
                android.app.PendingIntent.FLAG_IMMUTABLE,
            )
            startActivityAndCollapse(pi)
            return
        }
        AppGraph.connection.toggle()
    }

    override fun onDestroy() { scope.cancel(); super.onDestroy() }

    companion object {
        fun requestRefresh(ctx: Context) = requestListeningState(ctx, ComponentName(ctx, ZephyrTileService::class.java))
    }
}
