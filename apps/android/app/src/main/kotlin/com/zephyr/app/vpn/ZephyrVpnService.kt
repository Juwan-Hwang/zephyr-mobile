package com.zephyr.app.vpn

import android.app.Notification
import android.content.Intent
import android.content.pm.ServiceInfo
import android.net.VpnService
import android.os.Build
import android.os.ParcelFileDescriptor
import androidx.core.app.NotificationManagerCompat
import androidx.core.app.ServiceCompat
import com.zephyr.app.di.AppGraph
import com.zephyr.app.tile.ZephyrTileService
import com.zephyr.app.widget.ZephyrWidget
import com.zephyr.engine.ConnectionStatus
import com.zephyr.engine.TrafficSample
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.debounce
import kotlinx.coroutines.flow.drop
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.onStart
import kotlinx.coroutines.launch

/**
 * Foreground VPN service: builds the tun, hands it to the core, keeps the ongoing notification fresh (1 Hz)
 * and mirrors state to the QS tile and widget. Also owns on-demand and trusted Wi‑Fi (contract §16.a⑤, [OnDemand]):
 * START_STICKY + [ACTION_RESUME] reconnects, and a tunnel dropped on trusted Wi‑Fi keeps the service in the
 * foreground ("paused") so it can reconnect when the device leaves that network.
 */
class ZephyrVpnService : VpnService() {

    private var prober: kotlinx.coroutines.Job? = null
    private var pausedWatcher: Job? = null
    private val lifecycle = kotlinx.coroutines.sync.Mutex()
    /** Tunnel dropped on trusted Wi‑Fi, service still watching (contract §16.a⑤). */
    @Volatile private var paused = false
    /** §16.a③: a network switch asks the failover probe loop for its next round now. */
    private val probeNow = kotlinx.coroutines.channels.Channel<Unit>(kotlinx.coroutines.channels.Channel.CONFLATED)
    // Issue #208: a failed job is logged (AppGraph.guard), never the end of the process.
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default + AppGraph.guard + kotlinx.coroutines.CoroutineName("vpn service"))
    private var tun: ParcelFileDescriptor? = null
    private var watcher: Job? = null
    private var widgetTicker: Job? = null
    private var netWatcher: Job? = null
    private var bridge: TunBridge = TunBridge.Simulated
    private val engine get() = AppGraph.engine

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_DISCONNECT -> {
                // Contract §16.a⑤: a manual disconnect from any surface (UI, widget, QS tile, notification) pauses
                // on-demand until the next manual connect.
                OnDemand.markManualDisconnect(this)
                transition { stop() }
                return START_NOT_STICKY
            }
            ACTION_TOGGLE_MODE -> scope.launch { toggleMode() }
            ACTION_CONNECT -> { OnDemand.markManualConnect(this); start(auto = false) }
            // On-demand (boot / app update / network back) and the system's sticky restart after killing us.
            ACTION_RESUME, null -> start(auto = true)
            // android.net.VpnService: the system's 「始终开启的 VPN」 starts us; that is not on-demand's call to make.
            else -> start(auto = false)
        }
        return START_STICKY
    }

    /** Lifecycle changes (connect / pause / stop) run one at a time, never interleaved. */
    private fun transition(block: suspend () -> Unit) = scope.launch {
        lifecycle.withLock {
            try {
                block()
            } catch (c: kotlinx.coroutines.CancellationException) {
                throw c
            } catch (t: Exception) {
                // Issue #208: e.g. establish() refused / a core call threw mid-connect. Tear down and say why, instead of
                // leaving a half-built tunnel (or, before, crashing the app with it).
                AppGraph.report("vpn transition", t)
                runCatching { fail(com.zephyr.engine.ZephyrError(com.zephyr.engine.ErrorCode.CORE_CRASHED, "${t.javaClass.simpleName}: ${t.message}")) }
                    .onFailure { runCatching { stop() } }
            }
        }
    }

    private fun start(auto: Boolean) {
        // Review W-P2-4: the very first "连接中…" post uses the last known accent too, not a hard-coded blue.
        val first = Notifications.ongoing(this, null, null, emptyList(), connecting = true, accent = lastAccent)
        if (runCatching { ServiceCompat.startForeground(this, Notifications.ID_ONGOING, first, fgsType()) }.isFailure) {
            android.util.Log.w("Zephyr", "startForeground refused"); stopSelf(); return
        }
        running = true
        transition {
            if (auto && tun == null) {
                // A cold boot / sticky restart: wait for the stored settings, then ask on-demand (never prompt consent).
                AppGraph.settings.loaded.let { kotlinx.coroutines.withTimeoutOrNull(SETTINGS_WAIT_MS) { it.await() } }
                val s = engine.settings().first()
                val consent = prepare(this@ZephyrVpnService) == null
                if (!OnDemand.mayAutoConnect(s.onDemand, OnDemand.armed(this@ZephyrVpnService), consent)) { stop(); return@transition }
                // Issue #1: START_STICKY / network-up must not relaunch a failing core in a loop (ReconnectBackoff).
                val wait = OnDemand.autoWaitMs(this@ZephyrVpnService)
                if (wait == Long.MAX_VALUE) {
                    OnDemand.markManualDisconnect(this@ZephyrVpnService)
                    appLog(com.zephyr.engine.LogLevel.WARNING, "on-demand paused after ${ReconnectBackoff.MAX_FAILURES} failed starts; connect manually")
                    stop(); return@transition
                }
                if (wait > 0L) { scheduleRetry(applicationContext, wait); stop(); return@transition }
                val snap = AppGraph.network?.state?.value
                if (tun == null && snap?.network != null && OnDemand.onTrustedNetwork(s, snap.ssid, alwaysOnNow())) {
                    pause(snap.ssid)
                    return@transition
                }
            }
            if (tun == null) connectTunnel() else watch() // already up: re-post the live notification
        }
    }

    private suspend fun connectTunnel() {
        pausedWatcher?.cancel(); pausedWatcher = null
        paused = false
        noteAlwaysOn()
        val s = engine.settings().first()
        // Counted before anything can fail (pre-check, zm_start): a native crash mid-start still counts (ReconnectBackoff).
        OnDemand.beginAttempt(this)
        bridge = TunBridge.pick(this@ZephyrVpnService, engine, s, engine.connectionState().first().mode)
        val mock = (engine as? com.zephyr.engine.core.CoreEngine)?.usesMockData ?: true
        // Issue #1 (real device): which store the tunnel runs from goes to the logs page, so a report shows it.
        (engine as? com.zephyr.engine.core.CoreEngine)?.let { core ->
            appLog(com.zephyr.engine.LogLevel.INFO, "connect: native=${core.isNative} mock=$mock active=${core.activeSubscription() ?: "none"} bridge=${if (bridge.createsTun) "embedded" else "simulated"}")
        }
        if (!bridge.createsTun && !(com.zephyr.app.BuildConfig.DEBUG && mock)) {
            // Release never pretends: without a tunnel the app must not say "已连接" while traffic goes direct.
            // Issue #1: neither does a debug build on a real device (native libraries loaded, no mock data).
            fail(TunBridge.whyNoTunnel(engine)); return
        }
        if (bridge.createsTun && tun == null) {
            // Issue #1: check what can be checked before the tun exists — a tun nobody reads black-holes all traffic.
            bridge.preflight()?.let { err ->
                android.util.Log.e("Zephyr", "core pre-check failed: ${err.code}: ${err.message}")
                fail(err); return
            }
            tun = TunBridge.configure(Builder().setSession("Zephyr"), s.tun.mtu, s.tun.ipv6, s.tun.excludedApps, packageName).establish()
            // Issue #1: not `tun?.let { attach(it) } ?: …` — a successful attach is null too, and must not become an error.
            val established = tun
            val err = if (established == null) TunBridge.kernelError("establish() returned null") else bridge.attach(established)
            if (err != null) {
                android.util.Log.e("Zephyr", "core start failed: ${err.code}: ${err.message}")
                // Issue #1: close the tun right away, not only in stop(): until then the device has no route out.
                bridge.detach(); bridge = TunBridge.Simulated // detached once; tearDown() must not stop it again
                runCatching { tun?.close() }; tun = null
                fail(err); return
            }
        }
        runCatching { engine.connect() }.onFailure { t ->
            // Review A-P2-6: surface why, instead of silently falling back to "未连接".
            val e = (t as? com.zephyr.engine.ZephyrException)?.error
                ?: com.zephyr.engine.ZephyrError(com.zephyr.engine.ErrorCode.CORE_CRASHED, t.message ?: t.javaClass.simpleName)
            fail(e); return
        }
        OnDemand.attemptSucceeded(this)
        watch()
    }

    private fun watch() {
        watcher?.cancel()
        watcher = scope.launch {
            val power = getSystemService(android.os.PowerManager::class.java)
            var lastKey: Any? = null
            var lastAt = 0L
            combine(
                engine.connectionState(),
                engine.traffic().onStart { emit(TrafficSample(0, 0, 0)) },
                engine.scenes(),
                engine.settings(),
            ) { c, t, sc, st -> arrayOf(c, t, sc, st) }.collect { a ->
                val c = a[0] as com.zephyr.engine.ConnectionState
                val t = a[1] as TrafficSample
                @Suppress("UNCHECKED_CAST") val sc = a[2] as List<com.zephyr.engine.Scene>
                val st = a[3] as com.zephyr.engine.Settings
                if (c.status == ConnectionStatus.DISCONNECTED) return@collect
                // Review W-P2-1: state changes (mode, exits, accent) always post; pure speed samples only while the
                // screen is on and at most every MIN_POST_MS, so a locked phone isn't woken every second.
                val key = listOf(c.status, c.mode, c.globalNodeId, c.since, sc.map { it.selected.id }, st.accent)
                val now = android.os.SystemClock.elapsedRealtime()
                if (key == lastKey && (!power.isInteractive || now - lastAt < Notifications.MIN_POST_MS)) return@collect
                lastKey = key; lastAt = now; lastAccent = st.accent
                val global = if (c.mode == com.zephyr.engine.ProxyMode.GLOBAL) c.globalNodeId?.let { id -> runCatching { engine.node(id).summary.name }.getOrNull() } else null
                val n: Notification = Notifications.ongoing(this@ZephyrVpnService, c, t, sc, connecting = c.status == ConnectionStatus.CONNECTING, accent = st.accent, globalNode = global)
                postOngoing(n)
            }
        }
        // Widget: once now, then once a minute (today's usage, exits). Cancelled with the watcher on stop (review W-P1-1).
        widgetTicker?.cancel()
        widgetTicker = scope.launch {
            ZephyrTileService.requestRefresh(this@ZephyrVpnService)
            while (true) { ZephyrWidget.refreshAll(this@ZephyrVpnService); kotlinx.coroutines.delay(ZephyrWidget.LIVE_REFRESH_MS) }
        }
        (engine as? com.zephyr.engine.core.CoreEngine)?.let { core ->
            prober?.cancel()
            // Scene exits are probed once a minute while connected; core's failover tracker decides when to switch.
            // Contract §16.a③: a network switch runs the next round right away ([probeNow]).
            // Contract §16.c: failover probing is NOT gated by 「仅 Wi‑Fi 测速」 (one generate_204 per scene per minute;
            // skipping it would leave a broken scene broken on cellular). The stale-scene re-test is, inside core.
            // The app is excluded from its own tunnel, so NetworkMonitor sees the physical network.
            prober = scope.launch {
                while (true) {
                    kotlinx.coroutines.withTimeoutOrNull(PROBE_EVERY_MS) { probeNow.receive() }
                    val metered = AppGraph.network?.state?.value?.metered
                        ?: (getSystemService(android.net.ConnectivityManager::class.java)?.isActiveNetworkMetered ?: false)
                    runCatching { core.probeScenes(metered = metered) }
                    runCatching { core.retestStaleScenes(metered = metered) }
                }
            }
        }
        watchNetwork()
    }

    /**
     * Contract §16.a② (audit E04): the VPN follows the real network — `setUnderlyingNetworks` tracks the default
     * network (null while there is none), so the VPN's metered/roaming flags are the real ones.
     * Contract §16.a③: after the default network settles on a different one (Wi‑Fi ↔ cellular, another SSID; 2 s
     * debounce), `closeAll` once, re-evaluate trusted Wi‑Fi (§16.a⑤), and run the failover probe now. No config
     * reload, no new tun.
     */
    private fun watchNetwork() {
        val monitor = AppGraph.network ?: return
        netWatcher?.cancel()
        netWatcher = scope.launch {
            launch {
                var lastNet: android.net.Network? = null
                var first = true
                monitor.state.collect { snap ->
                    if (first || snap.network != lastNet) {
                        runCatching { setUnderlyingNetworks(snap.network?.let { arrayOf(it) }) }
                        lastNet = snap.network; first = false
                    }
                }
            }
            val start = monitor.state.value
            var lastKey = NetworkMonitor.changeKey(start)
            var lastSsid = start.ssid
            @OptIn(kotlinx.coroutines.FlowPreview::class)
            monitor.state.drop(1).debounce(NETWORK_DEBOUNCE_MS).collect { snap ->
                val key = NetworkMonitor.changeKey(snap) ?: return@collect // offline is not a switch
                if (key == lastKey) return@collect
                val previousSsid = lastSsid
                lastKey = key; lastSsid = snap.ssid
                val settings = engine.settings().first()
                noteAlwaysOn()
                // System always-on VPN: never auto-disconnect (lockdown would cut the device off).
                if (!alwaysOnNow() && NetworkMonitor.shouldDisconnect(settings, previousSsid, snap.ssid)) {
                    android.util.Log.i("Zephyr", "trusted Wi‑Fi joined: disconnecting")
                    // Not inline: both paths cancel this very collector.
                    transition { if (tun != null) { if (settings.onDemand) pause(snap.ssid) else stop() } }
                    return@collect
                }
                runCatching { engine.closeAll() }
                probeNow.trySend(Unit)
            }
        }
    }

    /**
     * Contract §16.a⑤: dropped on a trusted Wi‑Fi with on-demand on. The tunnel is down but the service stays in the
     * foreground watching the network, and reconnects once the device is off every trusted network (an unknown
     * SSID counts as untrusted), on-demand is turned off (→ stop), or the user acts from the notification.
     */
    private suspend fun pause(ssid: String?) {
        tearDown()
        paused = true
        val accent = runCatching { engine.settings().first().accent }.getOrDefault(lastAccent)
        runCatching { ServiceCompat.startForeground(this, Notifications.ID_ONGOING, Notifications.pausedOnTrusted(this, ssid, accent), fgsType()) }
        ZephyrTileService.requestRefresh(this)
        ZephyrWidget.refreshAll(this)
        val monitor = AppGraph.network ?: return
        pausedWatcher?.cancel()
        pausedWatcher = scope.launch {
            @OptIn(kotlinx.coroutines.FlowPreview::class)
            combine(monitor.state.debounce(NETWORK_DEBOUNCE_MS), engine.settings()) { n, st -> n to st }.collect { (n, st) ->
                noteAlwaysOn()
                when (OnDemand.whilePaused(st, n.network != null, n.ssid, alwaysOnNow())) {
                    OnDemand.Paused.STAY -> Unit
                    OnDemand.Paused.RESUME -> transition {
                        if (paused && OnDemand.armed(this@ZephyrVpnService) && prepare(this@ZephyrVpnService) == null) {
                            android.util.Log.i("Zephyr", "left trusted Wi‑Fi: reconnecting")
                            connectTunnel()
                        } else if (paused) stop()
                    }
                    OnDemand.Paused.STOP -> transition { if (paused) stop() }
                }
            }
        }
    }

    private fun alwaysOnNow(): Boolean = Build.VERSION.SDK_INT >= 29 && isAlwaysOn

    private fun noteAlwaysOn() = OnDemand.setAlwaysOn(this, alwaysOnNow())

    private suspend fun fail(e: com.zephyr.engine.ZephyrError) {
        // Issue #1: the reason goes to the logs page too, not only logcat.
        appLog(com.zephyr.engine.LogLevel.ERROR, "connect failed [${e.code.name.lowercase()}]: ${e.message}")
        // Nothing to connect to / geodata missing: on-demand would only fail again on every boot / network change.
        // Any other core failure: retried on the backoff schedule, paused after ReconnectBackoff.MAX_FAILURES.
        val streak = OnDemand.failures(this).coerceAtLeast(1)
        val out = ReconnectBackoff.onFailure(e, streak)
        if (e.code != com.zephyr.engine.ErrorCode.CORE_CRASHED) OnDemand.attemptSucceeded(this) // no backoff streak for these
        if (out.disarm) {
            OnDemand.markManualDisconnect(this)
            appLog(com.zephyr.engine.LogLevel.WARNING, "on-demand paused until the next manual connect")
        }
        out.retryInMs?.let { ms ->
            appLog(com.zephyr.engine.LogLevel.INFO, "on-demand retry in ${ms / 1000}s (failure $streak/${ReconnectBackoff.MAX_FAILURES})")
            scheduleRetry(applicationContext, ms)
        }
        stop()
        (engine as? com.zephyr.engine.core.CoreEngine)?.reportConnectFailure(e)
    }

    private fun appLog(level: com.zephyr.engine.LogLevel, message: String) {
        (engine as? com.zephyr.engine.core.CoreEngine)?.appLog(level, message)
    }

    /** Without POST_NOTIFICATIONS (13+) the foreground notification stays system-managed; skip updates. */
    @android.annotation.SuppressLint("MissingPermission") // checked via areNotificationsEnabled()
    private fun postOngoing(n: Notification) {
        val nm = NotificationManagerCompat.from(this)
        if (nm.areNotificationsEnabled()) runCatching { nm.notify(Notifications.ID_ONGOING, n) }
    }

    private suspend fun toggleMode() {
        val mode = engine.connectionState().first().mode
        engine.setMode(if (mode == com.zephyr.engine.ProxyMode.GLOBAL) com.zephyr.engine.ProxyMode.RULE else com.zephyr.engine.ProxyMode.GLOBAL)
    }

    /** Tunnel down (engine, core, tun, watchers); the service itself is [stop]'s or [pause]'s call. */
    private suspend fun tearDown() {
        netWatcher?.cancel(); netWatcher = null
        prober?.cancel(); prober = null
        widgetTicker?.cancel(); widgetTicker = null
        watcher?.cancel()
        runCatching { engine.disconnect() }
        (engine as? com.zephyr.engine.core.CoreEngine)?.flushUsage()
        bridge.detach()
        tun?.close(); tun = null
    }

    private suspend fun stop() {
        pausedWatcher?.cancel(); pausedWatcher = null
        paused = false
        tearDown()
        running = false
        ZephyrTileService.requestRefresh(this)
        ZephyrWidget.refreshAll(this)
        ServiceCompat.stopForeground(this, ServiceCompat.STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    /**
     * The user turned the VPN off in system settings, or another VPN took over: treated as a manual disconnect so
     * on-demand does not fight it (contract §16.a⑤).
     */
    override fun onRevoke() { OnDemand.markManualDisconnect(this); transition { stop() } }

    /** Low-memory signal: return Go heap to the OS before the LMK picks the VPN process. */
    override fun onTrimMemory(level: Int) {
        super.onTrimMemory(level)
        if (level >= TRIM_MEMORY_RUNNING_LOW) com.zephyr.engine.core.Mihomo.trimMemory()
    }

    override fun onDestroy() {
        running = false
        scope.cancel()
        tun?.close()
        super.onDestroy()
    }

    private fun fgsType(): Int =
        if (Build.VERSION.SDK_INT >= 34) ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE else 0

    companion object {
        /** Last accent seen while connected; process-lifetime cache for the first foreground post (review W-P2-4). */
        @Volatile var lastAccent: com.zephyr.engine.Accent = com.zephyr.engine.Accent.BLUE
        /** True from start() until stop(): the service is up (connecting, connected, or paused on trusted Wi‑Fi). */
        @Volatile var running: Boolean = false; private set
        private const val PROBE_EVERY_MS = 60_000L
        /** Contract §16.a③: the network has to stay put this long before a switch counts. */
        const val NETWORK_DEBOUNCE_MS = 2_000L
        private const val SETTINGS_WAIT_MS = 3_000L
        const val ACTION_CONNECT = "com.juwanh.zephyr.CONNECT"
        const val ACTION_DISCONNECT = "com.juwanh.zephyr.DISCONNECT"
        const val ACTION_TOGGLE_MODE = "com.juwanh.zephyr.TOGGLE_MODE"
        /** On-demand's automatic (re)connect: never prompts consent, honours trusted Wi‑Fi. */
        const val ACTION_RESUME = "com.juwanh.zephyr.RESUME"

        @Volatile private var retryJob: Job? = null

        /** Issue #1: one pending backoff retry per process (replaces an earlier one); on-demand decides when it fires. */
        fun scheduleRetry(app: android.content.Context, delayMs: Long) {
            retryJob?.cancel()
            retryJob = AppGraph.appScope.launch {
                kotlinx.coroutines.delay(delayMs)
                val on = runCatching { AppGraph.engine.settings().first().onDemand }.getOrDefault(false)
                OnDemand.reconnectIfWanted(app, on, "backoff retry")
            }
        }
    }
}
