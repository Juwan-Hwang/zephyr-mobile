package com.zephyr.app.vpn

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.net.VpnService
import androidx.core.content.ContextCompat
import com.zephyr.engine.Settings

/**
 * Contract §16.a⑤ (audit E01, Android semantics). Android has no system on-demand rules, so 「按需连接」 means
 * **auto-reconnect**: once the user has connected by hand, the tunnel comes back after the service is killed, the
 * process restarts, the device reboots, the app is updated, or the network returns from none — unless the user's
 * last action was a manual disconnect (from any surface), which pauses on-demand until the next manual connect.
 *
 * Never prompts VPN consent: an automatic start only happens when [VpnService.prepare] says consent is already
 * there. State lives in plain SharedPreferences so the boot receiver and a sticky restart read it synchronously.
 */
object OnDemand {
    private const val PREFS = "zephyr_on_demand"
    private const val KEY_ARMED = "armed"
    private const val KEY_ALWAYS_ON = "always_on"
    private const val KEY_FAILS = "connect_failures"
    private const val KEY_LAST_ATTEMPT = "last_attempt_at"

    private fun prefs(ctx: Context) = ctx.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    /**
     * True when the user's last manual action was "connect". False before the first manual connect (on-demand does
     * nothing until then) and after a manual disconnect (paused until the next manual connect).
     */
    fun armed(ctx: Context): Boolean = prefs(ctx).getBoolean(KEY_ARMED, false)
    /** A manual connect also forgets the failure streak ([ReconnectBackoff]). */
    fun markManualConnect(ctx: Context) = prefs(ctx).edit().putBoolean(KEY_ARMED, true).putInt(KEY_FAILS, 0).putLong(KEY_LAST_ATTEMPT, 0L).apply()
    fun markManualDisconnect(ctx: Context) = prefs(ctx).edit().putBoolean(KEY_ARMED, false).apply()

    // ── Issue #1: failure streak for [ReconnectBackoff] ─────────────────────────────────────────────
    /** Consecutive connect attempts that did not reach "connected" (an attempt whose process died included). */
    fun failures(ctx: Context): Int = prefs(ctx).getInt(KEY_FAILS, 0)
    fun lastAttemptAt(ctx: Context): Long = prefs(ctx).getLong(KEY_LAST_ATTEMPT, 0L)

    /**
     * Counts an attempt before the core starts. Written synchronously: a native crash in `zm_start` kills the
     * process, and the sticky restart must see this attempt.
     */
    fun beginAttempt(ctx: Context, now: Long = System.currentTimeMillis()) {
        prefs(ctx).edit().putInt(KEY_FAILS, failures(ctx) + 1).putLong(KEY_LAST_ATTEMPT, now).commit()
    }

    /** Connected, or the failure was not the core's (no backoff for those): the streak is over. */
    fun attemptSucceeded(ctx: Context) {
        if (failures(ctx) != 0) prefs(ctx).edit().putInt(KEY_FAILS, 0).putLong(KEY_LAST_ATTEMPT, 0L).apply()
    }

    /** Ms an automatic start still has to wait, 0 = go; [Long.MAX_VALUE] = streak exhausted (manual connect only). */
    fun autoWaitMs(ctx: Context, now: Long = System.currentTimeMillis()): Long {
        val n = failures(ctx)
        if (ReconnectBackoff.exhausted(n)) return Long.MAX_VALUE
        return ReconnectBackoff.waitBeforeAuto(n, lastAttemptAt(ctx), now)
    }

    /**
     * Last `VpnService.isAlwaysOn()` the service saw (API 29+). The settings row can only learn it from a running
     * service, so it is cached (false until a service has run).
     */
    fun alwaysOn(ctx: Context): Boolean = prefs(ctx).getBoolean(KEY_ALWAYS_ON, false)
    fun setAlwaysOn(ctx: Context, on: Boolean) {
        if (alwaysOn(ctx) != on) prefs(ctx).edit().putBoolean(KEY_ALWAYS_ON, on).apply()
    }

    /** Pure rule: may Zephyr start the tunnel without the user asking right now? */
    fun mayAutoConnect(onDemand: Boolean, armed: Boolean, hasConsent: Boolean): Boolean = onDemand && armed && hasConsent

    /** Being on a trusted network that 「受信任时断开」 applies to. Unknown SSID (null) is never trusted. */
    fun onTrustedNetwork(settings: Settings, ssid: String?, alwaysOn: Boolean): Boolean =
        !alwaysOn && settings.disconnectOnTrusted && NetworkMonitor.isTrusted(settings, ssid)

    /** What a tunnel paused on trusted Wi‑Fi does after the network or the settings changed. */
    enum class Paused { STAY, RESUME, STOP }

    fun whilePaused(settings: Settings, hasNetwork: Boolean, ssid: String?, alwaysOn: Boolean): Paused = when {
        !settings.onDemand -> Paused.STOP
        !hasNetwork -> Paused.STAY // nothing to protect; the next network decides
        onTrustedNetwork(settings, ssid, alwaysOn) -> Paused.STAY
        else -> Paused.RESUME
    }

    /** Starts the tunnel if on-demand allows it (never asks for consent). Safe to call from any background context. */
    fun reconnectIfWanted(ctx: Context, onDemand: Boolean, why: String) {
        if (ZephyrVpnService.running) return
        val consent = VpnService.prepare(ctx) == null
        if (!mayAutoConnect(onDemand, armed(ctx), consent)) return
        // Issue #1: a core that keeps failing is retried on the backoff schedule only, not on every network change.
        val wait = autoWaitMs(ctx)
        if (wait > 0L) { android.util.Log.i("Zephyr", "on-demand reconnect ($why) deferred: backoff ${if (wait == Long.MAX_VALUE) "exhausted" else "${wait}ms"}"); return }
        android.util.Log.i("Zephyr", "on-demand reconnect ($why)")
        runCatching {
            ContextCompat.startForegroundService(ctx, Intent(ctx, ZephyrVpnService::class.java).setAction(ZephyrVpnService.ACTION_RESUME))
        }.onFailure { android.util.Log.w("Zephyr", "on-demand reconnect refused: ${it.message}") }
    }
}

/** Boot / app-update reconnect for 「按需连接」 (contract §16.a⑤); does nothing unless [OnDemand] allows it. */
class OnDemandReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            Intent.ACTION_BOOT_COMPLETED, Intent.ACTION_MY_PACKAGE_REPLACED -> Unit
            else -> return
        }
        if (!OnDemand.armed(context)) return // cheap exit before touching the engine
        // The settings store is async; the service re-checks onDemand and trusted Wi‑Fi itself after it starts.
        OnDemand.reconnectIfWanted(context, onDemand = true, why = intent.action ?: "boot")
    }
}
