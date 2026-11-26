package com.zephyr.app.vpn

import android.content.Context
import android.content.Intent
import android.net.VpnService
import androidx.core.content.ContextCompat
import com.zephyr.engine.ConnectionStatus
import com.zephyr.engine.ZephyrEngine
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch

/**
 * Single entry point for connect/disconnect from any surface (home toggle, QS tile, widget, notification).
 * Owns the VpnService handshake: the platform layer starts the tunnel, then the engine (contract §11).
 */
class ConnectionController(private val context: Context, private val engine: ZephyrEngine, private val scope: CoroutineScope) {

    /** Non-null when the user still has to grant VPN permission; launch it from an Activity. */
    fun permissionIntent(): Intent? = VpnService.prepare(context)

    /** Contract §16.b ②: true when nothing is imported yet (connecting would only fail with subscription_not_found). */
    suspend fun hasNoSubscription(): Boolean = runCatching { engine.subscriptionsSummary().count == 0 }.getOrDefault(false)

    fun connect() {
        scope.launch(kotlinx.coroutines.CoroutineName("connect")) {
            if (hasNoSubscription()) { openImport(); return@launch }
            connectNow()
        }
    }

    /**
     * Tile / widget / notification with no subscription: open the app on the import panel. Where the system does not
     * let the app come forward, the toast still says why nothing happened ("还没有订阅").
     */
    private fun openImport() {
        android.os.Handler(android.os.Looper.getMainLooper()).post {
            runCatching { android.widget.Toast.makeText(context, com.zephyr.app.R.string.connect_no_subscription, android.widget.Toast.LENGTH_SHORT).show() }
            runCatching {
                context.startActivity(
                    Intent(context, com.zephyr.app.MainActivity::class.java).setAction(ACTION_OPEN_IMPORT)
                        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP),
                )
            }
        }
    }

    private fun connectNow() {
        if (permissionIntent() != null) {
            // Surfaces without an Activity (tile/widget) bounce through the non-exported consent trampoline.
            context.startActivity(Intent(context, VpnPermissionActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
            return
        }
        OnDemand.markManualConnect(context) // §16.a⑤: arms on-demand (the service marks it again, harmless)
        // Issue #208: from the QS tile / widget this runs after the tap, in the background. On API 31+ the system may
        // refuse the start (ForegroundServiceStartNotAllowedException); uncaught, that killed the whole app. Retry it
        // from the consent trampoline, which is a foreground Activity (it connects right away when consent exists).
        attempt(
            what = "start vpn service",
            start = { ContextCompat.startForegroundService(context, Intent(context, ZephyrVpnService::class.java).setAction(ZephyrVpnService.ACTION_CONNECT)) },
            fallback = { context.startActivity(Intent(context, VpnPermissionActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) },
            report = com.zephyr.app.di.AppGraph::report,
        )
    }

    /** Manual disconnect from any surface: pauses on-demand until the next manual connect (contract §16.a⑤). */
    fun disconnect() {
        OnDemand.markManualDisconnect(context)
        // Issue #208: startService from the background throws (BackgroundServiceStartNotAllowedException) when the
        // service is not running; then there is no tunnel to stop, only the engine's state to reset.
        attempt(
            what = "stop vpn service",
            start = { context.startService(Intent(context, ZephyrVpnService::class.java).setAction(ZephyrVpnService.ACTION_DISCONNECT)) },
            fallback = { scope.launch { runCatching { engine.disconnect() }; com.zephyr.app.tile.ZephyrTileService.requestRefresh(context); com.zephyr.app.widget.ZephyrWidget.refreshAll(context) } },
            report = com.zephyr.app.di.AppGraph::report,
        )
    }

    companion object {
        /** Not exported as a filter: only this app's own explicit intents carry it. */
        const val ACTION_OPEN_IMPORT = "com.juwanh.zephyr.OPEN_IMPORT"

        /**
         * Runs [start]; if the platform refuses it (IllegalStateException covers ForegroundServiceStartNotAllowed /
         * BackgroundServiceStartNotAllowed, SecurityException a missing grant), reports why and runs [fallback].
         * Neither failure escapes: a throw here used to end the process (issue #208). Returns true when [start] ran.
         */
        internal fun attempt(what: String, start: () -> Unit, fallback: () -> Unit, report: (String, Throwable) -> Unit): Boolean {
            try {
                start(); return true
            } catch (e: IllegalStateException) {
                report(what, e)
            } catch (e: SecurityException) {
                report(what, e)
            }
            try { fallback() } catch (t: RuntimeException) { report("$what (fallback)", t) }
            return false
        }
    }

    fun toggle() {
        scope.launch(kotlinx.coroutines.CoroutineName("toggle")) {
            // A connected state with no service behind it is a stale one: the widget's power button then connects.
            val s = com.zephyr.app.widget.WidgetState.effectiveStatus(engine.connectionState().first().status, ZephyrVpnService.running)
            if (s == ConnectionStatus.CONNECTED || s == ConnectionStatus.CONNECTING) disconnect() else connect()
        }
    }
}
