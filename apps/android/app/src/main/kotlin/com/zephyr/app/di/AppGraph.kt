package com.zephyr.app.di

import android.content.Context
import com.zephyr.app.BuildConfig
import com.zephyr.app.vpn.ConnectionController
import com.zephyr.app.vpn.Notifications
import com.zephyr.engine.ZephyrEngine
import com.zephyr.engine.core.CoreEngine
import com.zephyr.engine.mock.MockEngine
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob

/**
 * Process-wide object graph. Hand-rolled on purpose: three singletons don't justify a DI framework's
 * startup cost (cold start budget < 1 s on mid-range devices, spec §7).
 */
object AppGraph {
    lateinit var engine: ZephyrEngine; private set
    lateinit var settings: SettingsStore; private set
    lateinit var connection: ConnectionController; private set
    val appScope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
    @Volatile private var ready = false

    /** Demo mode (prototype "2:14:07" state) for store screenshots: build with -Pzephyr.demo=true. */
    val demo: Boolean get() = BuildConfig.DEMO

    fun init(context: Context) {
        if (ready) return
        val app = context.applicationContext
        // CoreEngine delegates to MockEngine until core-mobile ships the v0 surface over UniFFI.
        engine = CoreEngine(MockEngine(scope = appScope, demo = demo))
        settings = SettingsStore(app, engine, appScope)
        connection = ConnectionController(app, engine, appScope)
        Notifications.ensureChannels(app)
        ready = true
    }

    /** For tests / previews. */
    fun override(engine: ZephyrEngine) { this.engine = engine }
}
