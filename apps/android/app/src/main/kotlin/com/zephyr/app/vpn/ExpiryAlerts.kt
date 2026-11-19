package com.zephyr.app.vpn

import android.content.Context
import androidx.core.app.NotificationManagerCompat
import androidx.work.CoroutineWorker
import androidx.work.ExistingWorkPolicy
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import com.zephyr.app.di.AppGraph
import com.zephyr.design.format.ZFormat
import com.zephyr.engine.Subscription
import kotlinx.coroutines.flow.first
import java.time.Instant
import java.time.ZoneId
import java.util.concurrent.TimeUnit

/**
 * Contract §16.e ⑤ (U29): "Orbit 将于 11月9日 到期 · 剩余 12.0 GB".
 * - once per subscription per `expiresAt` value, 3 calendar days before the expiry date at 10:00 local time;
 * - learnt about inside those 3 days (and not expired): at the next check (hourly background check, app to the
 *   foreground, a subscription import / update) — right away;
 * - expired: never; a new `expiresAt` (renewal) is a new key, so it is planned again;
 * - Android 13+ without POST_NOTIFICATIONS (asked with the ongoing notification): nothing is posted;
 * - channel "订阅提醒" ([Notifications.CH_ALERTS]); tapping opens the subscriptions page.
 */
object ExpiryAlerts {
    const val DAYS_BEFORE = 3L
    const val HOUR = 10
    private const val PREFS = "zephyr.expiry"
    private const val KEY_SENT = "sent"

    /** 10:00 local, [DAYS_BEFORE] calendar days before the expiry date. */
    fun fireAt(expiresAt: Long, zone: ZoneId): Long =
        Instant.ofEpochMilli(expiresAt).atZone(zone).toLocalDate().minusDays(DAYS_BEFORE).atTime(HOUR, 0).atZone(zone).toInstant().toEpochMilli()

    fun key(s: Subscription): String = "${s.id}@${s.expiresAt}"

    data class Plan(val now: List<Subscription>, val nextAt: Long?)

    /** Pure: which subscriptions to notify at [now], and when the next one is due. */
    fun plan(subs: List<Subscription>, now: Long, zone: ZoneId, sent: Set<String>): Plan {
        val due = mutableListOf<Subscription>()
        var next: Long? = null
        for (s in subs) {
            val exp = s.expiresAt ?: continue
            if (exp <= now || key(s) in sent) continue
            val at = fireAt(exp, zone)
            if (at <= now) due += s else next = minOf(next ?: at, at)
        }
        return Plan(due, next)
    }

    /** [fromWorker]: re-arming from inside [ExpiryWorker] appends, since REPLACE would cancel the running job. */
    suspend fun check(ctx: Context, zone: ZoneId = ZoneId.systemDefault(), fromWorker: Boolean = false) {
        val subs = runCatching { AppGraph.engine.subscriptions().first() }.getOrNull() ?: return
        val prefs = ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val sent = prefs.getStringSet(KEY_SENT, emptySet()).orEmpty()
        val now = System.currentTimeMillis()
        val p = plan(subs, now, zone, sent)
        val nm = NotificationManagerCompat.from(ctx)
        if (p.now.isNotEmpty() && nm.areNotificationsEnabled()) {
            val posted = p.now.mapNotNull { s -> if (post(ctx, nm, s, zone)) key(s) else null }
            // Keys of subscriptions that are gone or renewed are dropped so the set stays small.
            val live = subs.map(::key).toSet()
            prefs.edit().putStringSet(KEY_SENT, (sent.filter { it in live } + posted).toSet()).apply()
        }
        p.nextAt?.let { schedule(ctx, it - now, if (fromWorker) ExistingWorkPolicy.APPEND_OR_REPLACE else ExistingWorkPolicy.REPLACE) }
    }

    @android.annotation.SuppressLint("MissingPermission") // areNotificationsEnabled() checked by the caller
    private fun post(ctx: Context, nm: NotificationManagerCompat, s: Subscription, zone: ZoneId): Boolean = runCatching {
        val date = ZFormat.monthDay(ctx.resources, Instant.ofEpochMilli(s.expiresAt!!).atZone(zone).toLocalDate())
        nm.notify(s.id, Notifications.ID_EXPIRY, Notifications.expiry(ctx, s.name, date, s.remainingBytes?.let(ZFormat::bytesText)))
        true
    }.getOrDefault(false)

    private const val WORK = "zephyr.subscriptions.expiry"

    fun schedule(ctx: Context, delayMs: Long, policy: ExistingWorkPolicy = ExistingWorkPolicy.REPLACE) {
        val req = OneTimeWorkRequestBuilder<ExpiryWorker>().setInitialDelay(delayMs.coerceAtLeast(0), TimeUnit.MILLISECONDS).build()
        runCatching { WorkManager.getInstance(ctx).enqueueUniqueWork(WORK, policy, req) }
    }
}

/** Fires at the planned 10:00; [ExpiryAlerts.check] posts and re-arms for the next one. */
class ExpiryWorker(ctx: Context, params: WorkerParameters) : CoroutineWorker(ctx, params) {
    override suspend fun doWork(): Result {
        AppGraph.init(applicationContext)
        AppGraph.settings.loaded.await()
        runCatching { ExpiryAlerts.check(applicationContext, fromWorker = true) }
        return Result.success()
    }
}
