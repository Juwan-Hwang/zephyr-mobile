package com.zephyr.app.vpn

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.result.contract.ActivityResultContracts
import com.zephyr.app.di.AppGraph

/**
 * Invisible, non-exported trampoline for surfaces without an Activity (QS tile, widget, notification) that need the
 * one-time VPN consent dialog before connecting (review A-P1-4). Being `exported="false"`, no other app or web page
 * can make Zephyr start a tunnel; MainActivity no longer accepts a connect action at all.
 */
class VpnPermissionActivity : ComponentActivity() {
    private val consent = registerForActivityResult(ActivityResultContracts.StartActivityForResult()) { r ->
        if (r.resultCode == RESULT_OK) AppGraph.connection.connect()
        finish()
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        AppGraph.init(this)
        if (savedInstanceState != null) return // the consent dialog is already up; its result finishes us
        val ask = AppGraph.connection.permissionIntent()
        if (ask == null) { AppGraph.connection.connect(); finish() } else consent.launch(ask)
    }
}
