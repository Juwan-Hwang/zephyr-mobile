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
            engine.settings().drop(1).collect { s ->
                context.store.edit { it[keySettings] = json.encodeToString(Settings.serializer(), s) }
            }
        }
    }

    suspend fun setOnboarded() { context.store.edit { it[keyOnboarded] = "1" } }
}
