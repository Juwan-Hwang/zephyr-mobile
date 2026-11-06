package com.zephyr.app

import android.content.Intent
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.SystemBarStyle
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.result.contract.ActivityResultContracts
import androidx.lifecycle.lifecycleScope
import com.zephyr.app.di.AppGraph
import com.zephyr.app.ui.nav.AppRoot
import com.zephyr.engine.ImportSource
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking

class MainActivity : ComponentActivity() {
    private val vpnPermission = registerForActivityResult(ActivityResultContracts.StartActivityForResult()) { r ->
        if (r.resultCode == RESULT_OK) AppGraph.connection.connect()
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        enableEdgeToEdge(SystemBarStyle.auto(android.graphics.Color.TRANSPARENT, android.graphics.Color.TRANSPARENT))
        super.onCreate(savedInstanceState)
        // DataStore read is a few ms on first frame; avoids a flash of onboarding for returning users.
        val onboard = !AppGraph.demo && runBlocking { !AppGraph.settings.onboarded.first() }
        setContent {
            AppRoot(onToggle = { on -> if (on) requestConnect() else AppGraph.connection.disconnect() }, startOnboarding = onboard)
        }
        handle(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handle(intent)
    }

    private fun requestConnect() {
        val ask = AppGraph.connection.permissionIntent()
        if (ask != null) vpnPermission.launch(ask) else AppGraph.connection.connect()
    }

    /** ACTION_CONNECT from tile/widget; clash://install-config?url=… and zephyr://import?url=… deep links. */
    private fun handle(intent: Intent?) {
        when {
            intent?.action == ACTION_CONNECT -> requestConnect()
            intent?.data != null -> {
                val url = intent.data?.getQueryParameter("url") ?: return
                lifecycleScope.launch { runCatching { AppGraph.engine.importSubscription(ImportSource.URL, url) } }
            }
        }
    }

    companion object { const val ACTION_CONNECT = "com.zephyr.app.ACTION_CONNECT" }
}
