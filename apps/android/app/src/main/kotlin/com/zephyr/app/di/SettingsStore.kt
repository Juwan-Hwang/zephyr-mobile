package com.zephyr.app.di

import android.content.Context
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import com.zephyr.engine.Settings
import com.zephyr.engine.ZephyrEngine
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.drop
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.launch
import kotlinx.serialization.json.Json

private val Context.store by preferencesDataStore("zephyr")

/**
 * Persists engine [Settings] locally (never backed up — see data_extraction_rules) and replays them into the
 * engine at launch. Also stores UI-only flags (onboarding done).
 */
class SettingsStore(private val context: Context, private val engine: ZephyrEngine, scope: CoroutineScope) {
    private val json = Json { ignoreUnknownKeys = true; encodeDefaults = false }
    private val keySettings = stringPreferencesKey("settings_v0")
    private val keyOnboarded = stringPreferencesKey("onboarded")

    val onboarded = context.store.data.map { it[keyOnboarded] == "1" }
    private val keyScrubHint = stringPreferencesKey("scrub_hint_seen")
    val scrubHintSeen = context.store.data.map { it[keyScrubHint] == "1" }
    suspend fun setScrubHintSeen() { context.store.edit { it[keyScrubHint] = "1" } }

    init {
        scope.launch {
            context.store.data.first()[keySettings]?.let { raw ->
                runCatching { json.decodeFromString(Settings.serializer(), raw) }.getOrNull()?.let { engine.updateSettings(it) }
            }
            launch { engine.settings().collect { s -> syncSystemNightMode(s.appearance) } }
            engine.settings().drop(1).collect { s ->
                context.store.edit { it[keySettings] = json.encodeToString(Settings.serializer(), s) }
            }
        }
    }

    suspend fun setOnboarded() { context.store.edit { it[keyOnboarded] = "1" } }

    /**
     * Review A-P2-3: tell the system the app's own appearance so the launch window and splash screen draw in it
     * (API 31+). Without this a forced dark/light app flashes one frame of the system theme on cold start.
     */
    private var lastNightMode = -1
    private fun syncSystemNightMode(a: com.zephyr.engine.Appearance) {
        if (android.os.Build.VERSION.SDK_INT < android.os.Build.VERSION_CODES.S) return
        val mode = when (a) {
            com.zephyr.engine.Appearance.DARK -> android.app.UiModeManager.MODE_NIGHT_YES
            com.zephyr.engine.Appearance.LIGHT -> android.app.UiModeManager.MODE_NIGHT_NO
            com.zephyr.engine.Appearance.SYSTEM -> android.app.UiModeManager.MODE_NIGHT_AUTO
        }
        if (mode == lastNightMode) return
        lastNightMode = mode
        runCatching { context.getSystemService(android.app.UiModeManager::class.java)?.setApplicationNightMode(mode) }
    }
}
