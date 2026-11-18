package com.zephyr.app.vpn

import android.content.Context
import androidx.work.Constraints
import androidx.work.CoroutineWorker
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.NetworkType
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import com.zephyr.app.di.AppGraph
import com.zephyr.engine.core.CoreEngine
import java.util.concurrent.TimeUnit

/**
 * Hourly sweep for subscriptions whose own auto-update interval has elapsed (core's `dueSubscriptions`).
 * Hourly is the floor, not the cadence: a 24 h subscription is fetched once a day. Needs a network — an
 * unmetered one while 「仅 Wi‑Fi 更新」 is on (audit E30) — and prefers not to run on a low battery;
 * WorkManager survives reboots and app death. Manual「立即更新」 is not affected.
 */
class SubscriptionWorker(ctx: Context, params: WorkerParameters) : CoroutineWorker(ctx, params) {
    override suspend fun doWork(): Result {
        AppGraph.init(applicationContext)
        val core = AppGraph.engine as? CoreEngine ?: return Result.success()
        return runCatching { core.updateDue() }.fold({ Result.success() }, { Result.retry() })
    }

    companion object {
        private const val NAME = "zephyr.subscriptions.due"
        fun networkType(wifiOnly: Boolean): NetworkType = if (wifiOnly) NetworkType.UNMETERED else NetworkType.CONNECTED

        /** UPDATE keeps the period's progress and swaps the constraints when the setting changes. */
        fun schedule(ctx: Context, wifiOnly: Boolean) {
            val req = PeriodicWorkRequestBuilder<SubscriptionWorker>(1, TimeUnit.HOURS)
                .setConstraints(Constraints.Builder().setRequiredNetworkType(networkType(wifiOnly)).setRequiresBatteryNotLow(true).build())
                .build()
            runCatching { WorkManager.getInstance(ctx).enqueueUniquePeriodicWork(NAME, ExistingPeriodicWorkPolicy.UPDATE, req) }
        }
    }
}
