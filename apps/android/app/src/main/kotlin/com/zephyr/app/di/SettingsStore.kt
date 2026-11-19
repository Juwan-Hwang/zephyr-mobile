package com.zephyr.app.di

import android.content.Context
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import com.zephyr.engine.Settings
import com.zephyr.engine.ZephyrEngine
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.launch

private val Context.store by preferencesDataStore("zephyr")

/**
 * Persists engine [Settings] locally (never backed up — see data_extraction_rules) and replays them into the
 * engine at launch. Also stores UI-only flags (onboarding done).
 */
class SettingsStore(private val context: Context, private val engine: ZephyrEngine, scope: CoroutineScope) {
    private val keySettings = stringPreferencesKey("settings_v0")
    private val keyOnboarded = stringPreferencesKey("onboarded")

    val onboarded = context.store.data.map { it[keyOnboarded] == "1" }
    private val keyScrubHint = stringPreferencesKey("scrub_hint_seen")
    val scrubHintSeen = context.store.data.map { it[keyScrubHint] == "1" }
    suspend fun setScrubHintSeen() { context.store.edit { it[keyScrubHint] = "1" } }

    /** Completes once the stored settings were replayed into the engine (a cold boot reconnect waits for it). */
    val loaded = kotlinx.coroutines.CompletableDeferred<Unit>()

    init {
        scope.launch {
            runCatching {
                context.store.data.first()[keySettings]?.let { raw ->
                    // Contract §16.c (E42): field-by-field decoding; a bad or missing field falls back on its own.
                    runCatching { engine.updateSettings(com.zephyr.engine.SettingsCodec.decode(raw)) }
                }
            }
            loaded.complete(Unit)
            // Audit E30: the subscription sweep follows 「仅 Wi‑Fi 更新」 (UNMETERED constraint), re-armed when it changes.
            launch {
                engine.settings().map { it.updateOnWifiOnly }.distinctUntilChanged()
                    .collect { com.zephyr.app.vpn.SubscriptionWorker.schedule(context, wifiOnly = it) }
            }
            // Audit E44: the usage widget rolls over to an empty day at local midnight even while disconnected.
            com.zephyr.app.widget.MidnightWidgetWorker.schedule(context)
            launch { engine.settings().collect { s -> syncSystemNightMode(s.appearance) } }
            // §16.c: a failed write rolls the engine back to the last stored value and says so (toast); never silent.
            // No drop(1): a change landing between this read and the collect below is still written.
            var persisted = engine.settings().first()
            engine.settings().collect { s ->
                if (s == persisted) return@collect
                runCatching { context.store.edit { it[keySettings] = com.zephyr.engine.SettingsCodec.encode(s) } }
                    .onSuccess { persisted = s }
                    .onFailure { t ->
                        android.util.Log.w("Zephyr", "settings write failed: ${t.message}")
                        val back = persisted
                        runCatching { engine.updateSettings(back) }
                        settingsFailed(context)
                    }
            }
        }
    }

    private suspend fun settingsFailed(ctx: Context) = kotlinx.coroutines.withContext(kotlinx.coroutines.Dispatchers.Main) {
        android.widget.Toast.makeText(ctx, com.zephyr.app.R.string.settings_save_failed, android.widget.Toast.LENGTH_SHORT).show()
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

/**
 * Trusted Wi‑Fi list edits (audit #208 U10; iOS TrustedWifiView): names are trimmed, kept unique and in the order
 * added. Pure so the library page and tests share one rule; the engine settings flow persists the result.
 */
object TrustedWifi {
    fun normalize(name: String): String = name.trim()

    /** Contract §16.c: an SSID is 1–32 bytes of UTF‑8; the list holds at most 50. */
    fun valid(name: String): Boolean = com.zephyr.engine.SettingsCodec.validSsid(name)

    /** Null when [name] is blank, longer than 32 bytes, already listed, or the list is full (nothing to write). */
    fun add(s: Settings, name: String): Settings? {
        val n = normalize(name)
        if (!valid(n) || n in s.trustedWifi || s.trustedWifi.size >= com.zephyr.engine.SettingsCodec.TRUSTED_WIFI_MAX) return null
        return s.copy(trustedWifi = s.trustedWifi + n)
    }

    fun remove(s: Settings, name: String): Settings = s.copy(trustedWifi = s.trustedWifi.filterNot { it == name })
}

suspend fun ZephyrEngine.addTrustedWifi(name: String): Boolean =
    TrustedWifi.add(settings().first(), name)?.let { updateSettings(it); true } ?: false

suspend fun ZephyrEngine.removeTrustedWifi(name: String) = updateSettings(TrustedWifi.remove(settings().first(), name))
