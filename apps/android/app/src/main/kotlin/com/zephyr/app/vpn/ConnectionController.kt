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
        scope.launch {
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
        ContextCompat.startForegroundService(context, Intent(context, ZephyrVpnService::class.java).setAction(ZephyrVpnService.ACTION_CONNECT))
    }

    /** Manual disconnect from any surface: pauses on-demand until the next manual connect (contract §16.a⑤). */
    fun disconnect() {
        OnDemand.markManualDisconnect(context)
        context.startService(Intent(context, ZephyrVpnService::class.java).setAction(ZephyrVpnService.ACTION_DISCONNECT))
    }

    companion object {
        /** Not exported as a filter: only this app's own explicit intents carry it. */
        const val ACTION_OPEN_IMPORT = "com.juwanh.zephyr.OPEN_IMPORT"
    }

    fun toggle() {
        scope.launch {
            val s = engine.connectionState().first().status
            if (s == ConnectionStatus.CONNECTED || s == ConnectionStatus.CONNECTING) disconnect() else connect()
        }
    }
}
