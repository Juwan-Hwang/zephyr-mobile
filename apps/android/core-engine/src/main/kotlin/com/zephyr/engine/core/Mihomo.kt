package com.zephyr.engine.core

import com.sun.jna.Library
import com.sun.jna.Native
import com.sun.jna.Pointer
import com.sun.jna.ptr.LongByReference

/**
 * Embedded mihomo (mihomo-mobile, Go c-shared `libzmihomo.so`) over its C ABI. In-process only — Android
 * forbids spawning the core as a child process inside VpnService, and it would double the memory.
 *
 * Every `char*` returned is either null (ok) or an error string owned by Go that must go back through zm_free.
 */
object Mihomo {
    private interface Lib : Library {
        fun zm_start(home: String, config: String, ctlSock: String): Pointer?
        fun zm_reload(config: String): Pointer?
        fun zm_stop()
        fun zm_running(): Int
        fun zm_traffic(up: LongByReference, down: LongByReference, upTotal: LongByReference, downTotal: LongByReference)
        fun zm_memory(): Long
        fun zm_set_memory_limit(bytes: Long)
        fun zm_free_os_memory()
        fun zm_version(): Pointer?
        fun zm_free(p: Pointer?)
        fun zm_logs(since: Long, minLevel: String, limit: Int): Pointer?
        fun zm_url_test(proxiesJson: String, url: String, timeoutMs: Int, concurrency: Int): Pointer?
        fun zm_set_geodata_timeout(ms: Long)
    }

    private val lib: Lib? by lazy { runCatching { Native.load("zmihomo", Lib::class.java) }.getOrNull() }

    val available: Boolean get() = lib != null

    data class Traffic(val upBps: Long, val downBps: Long, val upTotal: Long, val downTotal: Long)

    private fun Lib.take(p: Pointer?): String? = p?.let { val s = it.getString(0, "UTF-8"); zm_free(it); s }

    /** Only when the library itself could not be loaded (dlopen / JNA failed). */
    const val LIB_MISSING = "libzmihomo missing"

    /**
     * Issue #1 (S25 Ultra, e244006): `lib?.run { take(zm_start(…)) } ?: "libzmihomo missing"` — zm_start's null is
     * success, and the elvis turned every successful start into "libzmihomo missing", so the app stopped a core that had
     * started and showed the wrong reason. [LIB_MISSING] now only when [loaded] is false; otherwise the call's own answer.
     */
    inline fun callResult(loaded: Boolean, call: () -> String?): String? = if (loaded) call() else LIB_MISSING

    /** Starts the core; returns null on success or mihomo's error text. */
    fun start(home: String, config: String, ctlSock: String): String? { val l = lib; return callResult(l != null) { l!!.take(l.zm_start(home, config, ctlSock)) } }
    fun reload(config: String): String? { val l = lib; return callResult(l != null) { l!!.take(l.zm_reload(config)) } }
    fun stop() { lib?.zm_stop() }
    val running: Boolean get() = (lib?.zm_running() ?: 0) != 0
    val version: String? get() = lib?.run { take(zm_version()) }
    val memory: Long get() = lib?.zm_memory() ?: 0

    /** Soft Go heap cap; keeps the VPN process well under low-memory-killer pressure on 4 GB devices. */
    fun setMemoryLimit(bytes: Long) { lib?.zm_set_memory_limit(bytes) }
    fun trimMemory() { lib?.zm_free_os_memory() }

    /**
     * Contract §20.b: total time `zm_start` / `zm_reload` may spend downloading missing geodata. 0 = local files only
     * (missing → immediate `geodata missing:`), negative = default 15000 ms. False when the library is absent or older
     * than the symbol (JNA resolves it on first call).
     */
    fun setGeodataTimeout(ms: Long): Boolean = lib?.let { runCatching { it.zm_set_geodata_timeout(ms) }.isSuccess } ?: false

    fun traffic(): Traffic? = lib?.let { l ->
        val a = LongByReference(); val b = LongByReference(); val c = LongByReference(); val d = LongByReference()
        l.zm_traffic(a, b, c, d)
        Traffic(a.value, b.value, c.value, d.value)
    }

    /** In-process ring buffer (500 lines): `{"seq":n,"lines":[{seq,level,msg,at}]}` newer than [since]. */
    fun logs(since: Long, minLevel: String, limit: Int): String? = lib?.run { take(zm_logs(since, minLevel, limit)) }

    /** Newest sequence number in the ring (0 without the library); lines written after this are newer than it. */
    fun logSeq(): Long = logs(Long.MAX_VALUE, "error", 1)?.let { LogsJson.parse(it).seq } ?: 0L

    /**
     * Issue #1: `zm_start` succeeds even when the TUN listener failed (mihomo only logs it). Waits up to [timeoutMs]
     * for the TUN verdict in the lines after [since]; null = listening or no verdict in time (not treated as failure).
     */
    suspend fun tunStartError(since: Long, timeoutMs: Long = 1_500, pollMs: Long = 50): String? {
        if (lib == null) return null
        val deadline = System.currentTimeMillis() + timeoutMs
        while (true) {
            val lines = logs(since, "info", 200)?.let { LogsJson.parse(it).lines.map { l -> l.message } }.orEmpty()
            when (val o = TunStartCheck.outcome(lines)) {
                is TunStartCheck.Outcome.Failed -> return TunStartCheck.message(o)
                TunStartCheck.Outcome.Listening -> return null
                null -> Unit
            }
            if (System.currentTimeMillis() >= deadline) return null
            kotlinx.coroutines.delay(pollMs)
        }
    }

    /**
     * Temporary outbounds from core `latencyTestBatch` JSON, tested without zm_start (contract §14.w).
     * Returns `{"results":[{name,ms}]}` or `{"error":…}`; blocking, call off the main thread.
     */
    fun urlTest(proxiesJson: String, url: String, timeoutMs: Int, concurrency: Int): String? =
        lib?.run { take(zm_url_test(proxiesJson, url, timeoutMs, concurrency)) }
}
