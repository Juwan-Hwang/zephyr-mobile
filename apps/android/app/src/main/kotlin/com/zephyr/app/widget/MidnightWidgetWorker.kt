package com.zephyr.app.widget

import android.content.Context
import androidx.work.CoroutineWorker
import androidx.work.ExistingWorkPolicy
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import com.zephyr.app.di.AppGraph
import java.time.Duration
import java.time.ZoneId
import java.time.ZonedDateTime
import java.util.concurrent.TimeUnit

/**
 * Audit E44: today's-usage widgets only refresh while the tunnel runs (once a minute). Disconnected across
 * midnight they would keep showing yesterday's total, so a one-shot job fires just after local midnight,
 * redraws them (the ledger reads an earlier day as zero) and re-arms itself for the next midnight.
 * WorkManager may defer it a little under Doze; that is fine for a day rollover.
 */
class MidnightWidgetWorker(ctx: Context, params: WorkerParameters) : CoroutineWorker(ctx, params) {
    override suspend fun doWork(): Result {
        AppGraph.init(applicationContext)
        ZephyrWidget.refreshAll(applicationContext)
        // APPEND_OR_REPLACE: REPLACE from inside the running job would cancel this very run.
        schedule(applicationContext, policy = ExistingWorkPolicy.APPEND_OR_REPLACE)
        return Result.success()
    }

    companion object {
        private const val NAME = "zephyr.widget.midnight"
        /** A few seconds past midnight so the new local day is unambiguous. */
        private const val GRACE_MS = 5_000L

        /** Milliseconds from [now] to just after the next local midnight in [zone]. */
        fun delayToNextMidnight(now: ZonedDateTime): Long {
            val next = now.toLocalDate().plusDays(1).atStartOfDay(now.zone)
            return Duration.between(now, next).toMillis() + GRACE_MS
        }

        /** REPLACE re-aims the job after a time-zone change or a manual clock change on the next launch. */
        fun schedule(ctx: Context, zone: ZoneId = ZoneId.systemDefault(), policy: ExistingWorkPolicy = ExistingWorkPolicy.REPLACE) {
            val req = OneTimeWorkRequestBuilder<MidnightWidgetWorker>()
                .setInitialDelay(delayToNextMidnight(ZonedDateTime.now(zone)), TimeUnit.MILLISECONDS)
                .build()
            runCatching { WorkManager.getInstance(ctx).enqueueUniqueWork(NAME, policy, req) }
        }
    }
}
