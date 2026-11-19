package com.zephyr.app.ui.settings

import android.widget.Toast
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.platform.LocalContext
import com.zephyr.app.R
import com.zephyr.app.di.AppGraph
import com.zephyr.engine.Settings
import kotlinx.coroutines.launch

/**
 * Contract §16.c: settings rows apply optimistically; when the engine refuses (out of range) or a hot reload fails
 * (§16.b ③, already rolled back by the engine) the row snaps back and a toast says 未能应用更改. Disk write failures
 * are rolled back and reported by [com.zephyr.app.di.SettingsStore]. Never silent.
 */
@Composable
fun rememberSettingsWriter(): (Settings) -> Unit {
    val scope = rememberCoroutineScope()
    val ctx = LocalContext.current
    return remember(scope, ctx) {
        { next ->
            scope.launch {
                runCatching { AppGraph.engine.updateSettings(next) }.onFailure {
                    android.util.Log.w("Zephyr", "settings not applied: ${it.message}")
                    Toast.makeText(ctx, R.string.local_proxy_apply_failed, Toast.LENGTH_SHORT).show()
                }
            }
        }
    }
}
