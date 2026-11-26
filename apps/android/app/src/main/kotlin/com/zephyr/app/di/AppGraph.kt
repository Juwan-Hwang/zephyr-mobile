package com.zephyr.app.di

import android.content.Context
import com.zephyr.app.BuildConfig
import com.zephyr.app.vpn.ConnectionController
import com.zephyr.app.vpn.Notifications
import com.zephyr.engine.ZephyrEngine
import com.zephyr.engine.core.CoreEngine
import com.zephyr.engine.core.Mihomo
import com.zephyr.engine.core.RustLive
import com.zephyr.engine.mock.MockEngine
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.map

/**
 * Process-wide object graph. Hand-rolled on purpose: three singletons don't justify a DI framework's
 * startup cost (cold start budget < 1 s on mid-range devices, spec §7).
 */
object AppGraph {
    lateinit var engine: ZephyrEngine; private set
    lateinit var settings: SettingsStore; private set
    lateinit var connection: ConnectionController; private set
    /** The physical network under the tunnel; null under [override] (screenshot tests / previews). */
    var network: com.zephyr.app.vpn.NetworkMonitor? = null; private set
    /** False under [override] (screenshot tests / previews), where no SettingsStore exists. */
    val hasSettings: Boolean get() = ::settings.isInitialized
    /**
     * Issue #208: a failure in any fire-and-forget job here (toggle from the QS tile, widget, notification) used to
     * reach the thread's uncaught handler and kill the whole process. [guard] logs it to the logs page instead.
     */
    val guard: kotlinx.coroutines.CoroutineExceptionHandler = kotlinx.coroutines.CoroutineExceptionHandler { ctx, t ->
        report(ctx[kotlinx.coroutines.CoroutineName]?.name ?: "app", t)
    }
    val appScope = CoroutineScope(SupervisorJob() + Dispatchers.Default + guard)
    @Volatile private var ready = false

    /** Demo mode (prototype "2:14:07" state) for store screenshots: build with -Pzephyr.demo=true. */
    val demo: Boolean get() = BuildConfig.DEBUG && BuildConfig.DEMO // never in release, whatever flags were passed

    fun init(context: Context) {
        if (ready) return
        val app = context.applicationContext
        // Rust core (if its .so is packaged) for nodes/rules; MockEngine for the rest of the contract.
        val core = CoreEngine(
            MockEngine(scope = appScope, demo = demo),
            dataDir = java.io.File(app.filesDir, "core").apply { mkdirs() }.path,
            // Issue #1 (S25 Ultra): mock only when the native libraries are missing / failed to load, or in demo
            // mode; a debug build on a real device with the cores packaged shows the real (possibly empty) store.
            mockDataFor = { nativeLoaded -> CoreEngine.useMockData(BuildConfig.DEBUG, demo, nativeLoaded) },
            appVersion = BuildConfig.VERSION_NAME, // §16.i fetch User-Agent
            live = run {
                // Same socket TunBridge.Embedded hands to zm_start; only dialled while mihomo runs in-process.
                val rest by lazy { RustLive(com.zephyr.app.vpn.TunBridge.controllerSocket(app).path) }
                return@run { if (Mihomo.running) rest else null }
            },
        )
        // §16.i ⑤: no network at all → network_unavailable instead of a DNS failure. The app is outside its own VPN,
        // so its default network is the physical one.
        val cm = app.getSystemService(android.net.ConnectivityManager::class.java)
        core.online = { cm?.activeNetwork != null }
        engine = core
        // Issue #208: the crash the previous process recorded (CrashRecord, installed by ZephyrApplication) goes to 日志.
        CrashRecord(java.io.File(app.filesDir, CrashRecord.FILE_NAME)).takeLine()?.let { core.appLog(com.zephyr.engine.LogLevel.ERROR, it) }
        if (BuildConfig.DEBUG && BuildConfig.CORE_SEED > 0.0) appScope.launch { runCatching { core.seedMockNodes(BuildConfig.CORE_SEED) } }
        settings = SettingsStore(app, engine, appScope)
        network = com.zephyr.app.vpn.NetworkMonitor(app).also { m ->
            m.start()
            // Audit E08: ConnectionState.network is the real network (Release never shows the mock's「家」).
            appScope.launch {
                kotlinx.coroutines.flow.combine(m.state, core.settings()) { n, s -> com.zephyr.app.vpn.NetworkMonitor.info(n, s) }
                    .collect { core.setNetwork(it) }
            }
            // Contract §16.a⑤: 「按需连接」 also reconnects when the network comes back from none (e.g. the tunnel
            // failed to come up offline). The running service handles every other switch itself.
            // Issue #1: the first snapshot only records (unknown → known is not "the network came back").
            appScope.launch {
                val back = com.zephyr.app.vpn.NetworkReturn()
                m.state.collect { snap ->
                    if (back.update(snap.network != null) && !com.zephyr.app.vpn.ZephyrVpnService.running) {
                        settings.loaded.await()
                        val on = runCatching { core.settings().first().onDemand }.getOrDefault(false)
                        com.zephyr.app.vpn.OnDemand.reconnectIfWanted(app, on, "network up")
                    }
                }
            }
        }
        connection = ConnectionController(app, engine, appScope)
        // §16.e ⑤: (re)plan expiry alerts whenever a subscription or its expiry changes (import, update, renewal).
        appScope.launch {
            settings.loaded.await()
            core.subscriptions().map { l -> l.map { it.id to it.expiresAt } }.distinctUntilChanged()
                .collect { runCatching { com.zephyr.app.vpn.ExpiryAlerts.check(app) } }
        }
        Notifications.ensureChannels(app)
        ready = true
    }

    /**
     * A failure that must not crash the process (issue #208): logcat (tag Zephyr) and the logs page (日志) get the
     * same one-line reason. Safe before [init] and in JVM tests.
     */
    fun report(where: String, t: Throwable) {
        if (t is kotlinx.coroutines.CancellationException) return
        val line = "$where failed: ${t.javaClass.name}: ${t.message}"
        runCatching { android.util.Log.e("Zephyr", line, t) }
        val core = if (::engine.isInitialized) engine as? CoreEngine else null
        runCatching { core?.appLog(com.zephyr.engine.LogLevel.ERROR, line) }
    }

    /** For tests / previews: swaps the engine without a Context (no settings/connection). */
    fun override(engine: ZephyrEngine) { this.engine = engine }
}
