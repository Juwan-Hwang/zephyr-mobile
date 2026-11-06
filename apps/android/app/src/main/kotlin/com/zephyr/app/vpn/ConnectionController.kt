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

    fun connect() {
        if (permissionIntent() != null) {
            // Surfaces without an Activity (tile/widget) bounce through MainActivity to ask.
            context.startActivity(
                Intent(context, com.zephyr.app.MainActivity::class.java)
                    .setAction(com.zephyr.app.MainActivity.ACTION_CONNECT)
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
            )
            return
        }
        ContextCompat.startForegroundService(context, Intent(context, ZephyrVpnService::class.java).setAction(ZephyrVpnService.ACTION_CONNECT))
    }

    fun disconnect() {
        context.startService(Intent(context, ZephyrVpnService::class.java).setAction(ZephyrVpnService.ACTION_DISCONNECT))
    }

    fun toggle() {
        scope.launch {
            val s = engine.connectionState().first().status
            if (s == ConnectionStatus.CONNECTED || s == ConnectionStatus.CONNECTING) disconnect() else connect()
        }
    }
}
