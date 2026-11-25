package com.zephyr.app.vpn

import com.zephyr.engine.ErrorCode
import com.zephyr.engine.ZephyrError

/**
 * Issue #1 (S25 Ultra, comment 7152702939): a core that cannot start must not be relaunched forever by on-demand
 * (network back, START_STICKY restart, boot). Pure rules here; the counters live in [OnDemand]'s preferences.
 *
 * - `geodata missing:` (or a subscription that is gone / invalid): retrying cannot help → on-demand is paused until
 *   the user connects by hand (same as a manual disconnect).
 * - any other `core_crashed`: exponential backoff 30 s → 2 min → 10 min; after [MAX_FAILURES] consecutive failures
 *   on-demand is paused until the next manual connect.
 * - other errors keep today's behaviour (no automatic retry scheduled, on-demand stays armed).
 *
 * A failure counts from the moment an attempt starts ([OnDemand.beginAttempt]), so a native crash that kills the
 * process mid-`zm_start` still counts and the sticky restart backs off instead of looping.
 */
object ReconnectBackoff {
    /** Delays after the 1st and 2nd consecutive failure; the 3rd pauses on-demand. */
    val DELAYS_MS = longArrayOf(30_000L, 120_000L, 600_000L)
    const val MAX_FAILURES = 3
    const val GEODATA_MISSING = "geodata missing:"

    /** What to do after a failed connect. [retryInMs] null = no automatic retry. */
    data class Outcome(val disarm: Boolean, val retryInMs: Long?)

    fun isGeodataMissing(e: ZephyrError?): Boolean =
        e?.code == ErrorCode.CORE_CRASHED && e.message.trimStart().startsWith(GEODATA_MISSING, ignoreCase = true)

    /** [failures] = consecutive failed attempts including this one (≥ 1). */
    fun onFailure(e: ZephyrError, failures: Int): Outcome = when {
        e.code == ErrorCode.SUBSCRIPTION_NOT_FOUND || e.code == ErrorCode.SUBSCRIPTION_INVALID -> Outcome(disarm = true, retryInMs = null)
        isGeodataMissing(e) -> Outcome(disarm = true, retryInMs = null)
        e.code == ErrorCode.CORE_CRASHED ->
            if (failures >= MAX_FAILURES) Outcome(disarm = true, retryInMs = null)
            else Outcome(disarm = false, retryInMs = delayFor(failures))
        else -> Outcome(disarm = false, retryInMs = null)
    }

    /** Backoff after [failures] consecutive failures (1 → 30 s, 2 → 2 min, ≥ 3 → 10 min). */
    fun delayFor(failures: Int): Long = DELAYS_MS[(failures - 1).coerceIn(0, DELAYS_MS.size - 1)]

    /**
     * Before an automatic attempt: ms still to wait, or 0 when it may go now. [failures] are the attempts already
     * counted (an attempt whose process died mid-start included), [lastAttemptAt] when the last one began.
     */
    fun waitBeforeAuto(failures: Int, lastAttemptAt: Long, now: Long): Long {
        if (failures <= 0 || lastAttemptAt <= 0L) return 0L
        val due = lastAttemptAt + delayFor(failures)
        return (due - now).coerceAtLeast(0L)
    }

    /** Sticky restarts / network-up after this many unfinished-or-failed attempts are refused outright. */
    fun exhausted(failures: Int): Boolean = failures >= MAX_FAILURES
}

/**
 * Contract §16.a⑤ 「按需连接」 network-return trigger (issue #1): the first snapshot only records whether a network
 * exists — it is not "the network came back" — so a cold start never reconnects by itself.
 */
class NetworkReturn {
    /** null until the first snapshot. */
    private var had: Boolean? = null

    /** True only on a none → some transition after the first snapshot. */
    fun update(has: Boolean): Boolean {
        val fire = had == false && has
        had = has
        return fire
    }
}
