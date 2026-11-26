package com.zephyr.app.tile

import android.content.ComponentName
import android.content.Context
import android.graphics.drawable.Icon
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService
import com.zephyr.app.R
import com.zephyr.app.di.AppGraph
import com.zephyr.app.ui.common.labelRes
import com.zephyr.engine.ConnectionStatus
import com.zephyr.engine.ProxyMode
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.catch
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.launch

/** Quick Settings tile: "Zephyr / 规则 · 东京 03" (prototype `and`). Tap toggles; long-press opens the app. */
class ZephyrTileService : TileService() {
    // Issue #208: AppGraph.guard logs a failed job instead of letting it end the process.
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate + AppGraph.guard + kotlinx.coroutines.CoroutineName("tile"))
    private var job: Job? = null

    override fun onStartListening() {
        if (!safely("tile init") { AppGraph.init(this) }) return
        job?.cancel()
        job = scope.launch {
            // Issue #208: a core read error (scenes are re-read every few seconds) ends this collection, not the app.
            combine(AppGraph.engine.connectionState(), AppGraph.engine.scenes()) { c, s -> c to s }
                .catch { t -> AppGraph.report("tile state", t) }
                .collect { (raw, scenes) ->
                val tile = qsTile ?: return@collect
                // Same rule as the widget: connected / connecting only while the VPN service actually runs.
                val c = raw.copy(status = com.zephyr.app.widget.WidgetState.effectiveStatus(raw.status, com.zephyr.app.vpn.ZephyrVpnService.running))
                val on = c.status == ConnectionStatus.CONNECTED || c.status == ConnectionStatus.CONNECTING
                tile.state = if (on) Tile.STATE_ACTIVE else Tile.STATE_INACTIVE
                tile.label = getString(R.string.app_name)
                tile.icon = Icon.createWithResource(this@ZephyrTileService, R.drawable.ic_stat_zephyr)
                val mode = getString(c.mode.labelRes)
                // Global mode routes everything through the GLOBAL node, not the first scene's exit (review W-P2-2).
                val node = when (c.mode) {
                    ProxyMode.GLOBAL -> c.globalNodeId?.let { id -> runCatching { AppGraph.engine.node(id).summary.name }.getOrNull() }
                    ProxyMode.DIRECT -> null
                    // A scene without an exit yet is not named (it read 「未选择」).
                    ProxyMode.RULE -> com.zephyr.app.widget.WidgetState.ruleExit(com.zephyr.app.widget.WidgetState.sceneExits(scenes, emptyList()), emptyList())
                }
                val sub = when (c.status) {
                    ConnectionStatus.CONNECTING -> getString(R.string.common_status_connecting_ellipsis)
                    ConnectionStatus.CONNECTED -> listOfNotNull(mode, node).joinToString(" · ")
                    else -> getString(R.string.common_status_disconnected)
                }
                // Tile.subtitle is API 29+; on Android 9 the state goes into the content description only.
                if (android.os.Build.VERSION.SDK_INT >= 29) tile.subtitle = sub
                tile.contentDescription = getString(R.string.tile_a11y, getString(R.string.app_name), sub)
                tile.updateTile()
            }
        }
    }

    override fun onStopListening() { job?.cancel(); job = null }

    // Issue #208: anything thrown in onClick runs on the main thread and ended the process.
    override fun onClick() { safely("tile click") { click() } }

    private fun click() {
        AppGraph.init(this)
        if (AppGraph.connection.permissionIntent() != null) {
            // Needs an Activity to grant VPN permission.
            val intent = android.content.Intent(this, com.zephyr.app.vpn.VpnPermissionActivity::class.java)
                .addFlags(android.content.Intent.FLAG_ACTIVITY_NEW_TASK)
            if (android.os.Build.VERSION.SDK_INT >= 34) {
                startActivityAndCollapse(
                    android.app.PendingIntent.getActivity(this, 0, intent, android.app.PendingIntent.FLAG_IMMUTABLE),
                )
            } else {
                collapseTo(intent)
            }
            return
        }
        AppGraph.connection.toggle()
    }

    @android.annotation.SuppressLint("StartActivityAndCollapseDeprecated") // the only overload below API 34
    @Suppress("DEPRECATION")
    private fun collapseTo(intent: android.content.Intent) = startActivityAndCollapse(intent)

    override fun onDestroy() { scope.cancel(); super.onDestroy() }

    /** Runs [block]; a failure goes to logcat and 日志 instead of crashing. Returns whether it completed. */
    private inline fun safely(what: String, block: () -> Unit): Boolean = try { block(); true } catch (t: RuntimeException) { AppGraph.report(what, t); false }

    companion object {
        fun requestRefresh(ctx: Context) = requestListeningState(ctx, ComponentName(ctx, ZephyrTileService::class.java))
    }
}
