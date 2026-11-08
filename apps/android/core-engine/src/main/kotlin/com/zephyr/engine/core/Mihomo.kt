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
    }

    private val lib: Lib? by lazy { runCatching { Native.load("zmihomo", Lib::class.java) }.getOrNull() }

    val available: Boolean get() = lib != null

    data class Traffic(val upBps: Long, val downBps: Long, val upTotal: Long, val downTotal: Long)

    private fun Lib.take(p: Pointer?): String? = p?.let { val s = it.getString(0, "UTF-8"); zm_free(it); s }

    /** Starts the core; returns null on success or mihomo's error text. */
    fun start(home: String, config: String, ctlSock: String): String? = lib?.run { take(zm_start(home, config, ctlSock)) } ?: "libzmihomo missing"
    fun reload(config: String): String? = lib?.run { take(zm_reload(config)) } ?: "libzmihomo missing"
    fun stop() { lib?.zm_stop() }
    val running: Boolean get() = (lib?.zm_running() ?: 0) != 0
    val version: String? get() = lib?.run { take(zm_version()) }
    val memory: Long get() = lib?.zm_memory() ?: 0

    /** Soft Go heap cap; keeps the VPN process well under low-memory-killer pressure on 4 GB devices. */
    fun setMemoryLimit(bytes: Long) { lib?.zm_set_memory_limit(bytes) }
    fun trimMemory() { lib?.zm_free_os_memory() }

    fun traffic(): Traffic? = lib?.let { l ->
        val a = LongByReference(); val b = LongByReference(); val c = LongByReference(); val d = LongByReference()
        l.zm_traffic(a, b, c, d)
        Traffic(a.value, b.value, c.value, d.value)
    }

    /** In-process ring buffer (500 lines): `{"seq":n,"lines":[{seq,level,msg,at}]}` newer than [since]. */
    fun logs(since: Long, minLevel: String, limit: Int): String? = lib?.run { take(zm_logs(since, minLevel, limit)) }

    /**
     * Temporary outbounds from core `latencyTestBatch` JSON, tested without zm_start (contract §14.w).
     * Returns `{"results":[{name,ms}]}` or `{"error":…}`; blocking, call off the main thread.
     */
    fun urlTest(proxiesJson: String, url: String, timeoutMs: Int, concurrency: Int): String? =
        lib?.run { take(zm_url_test(proxiesJson, url, timeoutMs, concurrency)) }
}
