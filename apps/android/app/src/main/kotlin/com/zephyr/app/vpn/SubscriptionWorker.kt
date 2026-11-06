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
 * Hourly is the floor, not the cadence: a 24 h subscription is fetched once a day. Needs a network,
 * prefers not to run on a low battery; WorkManager survives reboots and app death.
 */
class SubscriptionWorker(ctx: Context, params: WorkerParameters) : CoroutineWorker(ctx, params) {
    override suspend fun doWork(): Result {
        AppGraph.init(applicationContext)
        val core = AppGraph.engine as? CoreEngine ?: return Result.success()
        return runCatching { core.updateDue() }.fold({ Result.success() }, { Result.retry() })
    }

    companion object {
        private const val NAME = "zephyr.subscriptions.due"
        fun schedule(ctx: Context) {
            val req = PeriodicWorkRequestBuilder<SubscriptionWorker>(1, TimeUnit.HOURS)
                .setConstraints(Constraints.Builder().setRequiredNetworkType(NetworkType.CONNECTED).setRequiresBatteryNotLow(true).build())
                .build()
            WorkManager.getInstance(ctx).enqueueUniquePeriodicWork(NAME, ExistingPeriodicWorkPolicy.KEEP, req)
        }
    }
}
