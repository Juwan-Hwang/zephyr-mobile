package com.zephyr.app.vpn

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import com.zephyr.app.di.AppGraph

/** Broadcast hook for surfaces that can't target the service directly (e.g. widgets on locked devices). */
class NotificationActionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        AppGraph.init(context)
        when (intent.action) {
            ZephyrVpnService.ACTION_DISCONNECT -> AppGraph.connection.disconnect()
            ZephyrVpnService.ACTION_CONNECT -> AppGraph.connection.connect()
        }
    }
}
