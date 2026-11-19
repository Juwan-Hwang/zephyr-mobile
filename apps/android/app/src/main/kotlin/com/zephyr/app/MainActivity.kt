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
import androidx.compose.runtime.mutableStateOf
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch

class MainActivity : ComponentActivity() {
    /** A clash:// / clashmeta:// / mihomo:// / zephyr:// deep link, waiting in the import sheet for the user to confirm. */
    private val pendingImport = mutableStateOf<String?>(null)
    /** Bumped to open the subscriptions page (expiry notification, §16.e ⑤). */
    private val openSubscriptions = mutableStateOf(0)
    /** Bumped to open the empty import panel (contract §16.b ②: connect with no subscription). */
    private val openImport = mutableStateOf(0)

    private val vpnPermission = registerForActivityResult(ActivityResultContracts.StartActivityForResult()) { r ->
        if (r.resultCode == RESULT_OK) AppGraph.connection.connect()
    }

    private val notifPermission = registerForActivityResult(ActivityResultContracts.RequestPermission()) { }

    /**
     * Android 13+: the ongoing notification (prototype 17) and expiry alerts need POST_NOTIFICATIONS. Asked once,
     * right after the first successful connection, when the user can see why, never at launch.
     */
    private fun askNotificationsAfterFirstConnect() {
        if (android.os.Build.VERSION.SDK_INT < 33) return
        val prefs = getSharedPreferences("zephyr.ui", MODE_PRIVATE)
        if (prefs.getBoolean("notif.asked", false)) return
        lifecycleScope.launch {
            AppGraph.engine.connectionState().first { it.status == com.zephyr.engine.ConnectionStatus.CONNECTED }
            val granted = checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS) == android.content.pm.PackageManager.PERMISSION_GRANTED
            prefs.edit().putBoolean("notif.asked", true).apply()
            if (!granted) notifPermission.launch(android.Manifest.permission.POST_NOTIFICATIONS)
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        enableEdgeToEdge(SystemBarStyle.auto(android.graphics.Color.TRANSPARENT, android.graphics.Color.TRANSPARENT))
        super.onCreate(savedInstanceState)
        // Review A-P2-1: read the onboarding flag off the main thread; the window background shows until the first
        // frame, so returning users still never see a flash of onboarding.
        lifecycleScope.launch {
            val onboard = !AppGraph.demo && !AppGraph.settings.onboarded.first()
            setContent {
                AppRoot(
                    onToggle = { on -> if (on) requestConnect() else AppGraph.connection.disconnect() },
                    startOnboarding = onboard,
                    pendingImport = pendingImport.value,
                    onImportShown = { pendingImport.value = null },
                    openImport = openImport.value,
                    openSubscriptions = openSubscriptions.value,
                )
            }
        }
        // Rotation / process recreation re-delivers the launch intent: handle it once only (review A-P1-4).
        if (savedInstanceState == null) handle(intent)
        askNotificationsAfterFirstConnect()
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handle(intent)
    }

    private fun requestConnect() {
        lifecycleScope.launch {
            // §16.b ②: no subscription → the import panel, never the VPN consent dialog or a doomed tunnel.
            if (AppGraph.connection.hasNoSubscription()) { openImport.value++; return@launch }
            val ask = AppGraph.connection.permissionIntent()
            if (ask != null) vpnPermission.launch(ask) else AppGraph.connection.connect()
        }
    }

    /**
     * clash:// · clashmeta:// · mihomo://install-config?url=… and zephyr://import?… (contract §15, single or several)
     * are BROWSABLE, so any web page can fire them. They only open the import sheet, where the parsed subscriptions,
     * their source and an http warning are listed; nothing is imported until the user taps 添加 (review A-P1-4,
     * audit U26). Connecting from the tile/widget goes through the non-exported VpnPermissionActivity, so this
     * exported Activity takes no connect action.
     */
    private fun handle(intent: Intent?) {
        val data = intent?.takeIf { it.action == Intent.ACTION_VIEW }?.data
        if (data != null && data.scheme?.lowercase() in DEEP_LINK_SCHEMES) pendingImport.value = data.toString()
        if (intent?.action == com.zephyr.app.vpn.ConnectionController.ACTION_OPEN_IMPORT) openImport.value++
        if (intent?.action == ACTION_OPEN_SUBSCRIPTIONS) openSubscriptions.value++
        setIntent(Intent(this, MainActivity::class.java))
    }

    override fun onStart() {
        super.onStart()
        // §16.e ⑤: back in the foreground is one of the checks that posts an expiry alert already due.
        lifecycleScope.launch { AppGraph.settings.loaded.await(); runCatching { com.zephyr.app.vpn.ExpiryAlerts.check(applicationContext) } }
    }

    companion object {
        const val ACTION_OPEN_SUBSCRIPTIONS = "com.juwanh.zephyr.OPEN_SUBSCRIPTIONS"
        private val DEEP_LINK_SCHEMES = setOf("clash", "clashmeta", "mihomo", "zephyr")
    }
}
