package com.zephyr.engine.core

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.sync.Semaphore
import kotlinx.coroutines.sync.withPermit
import kotlinx.coroutines.withContext
import java.net.InetSocketAddress
import java.net.Socket

/**
 * Contract §14.u: with the tunnel down, latency is the TCP handshake time to server:port, measured in the app
 * process. Handshake slots are shared process-wide (32); a failure or a 3 s timeout records -1.
 * Hosts are unmasked and never leave this class.
 */
object TcpPinger {
    const val TIMEOUT_MS = 3_000
    private val slots = Semaphore(32)

    /** Default probe for [CoreEngine]: real handshake with the 3 s timeout. */
    val probe: suspend (String, Int) -> Int = { h, p -> ping(h, p, TIMEOUT_MS) }

    /** Handshake time in ms, or -1. */
    suspend fun ping(host: String, port: Int, timeoutMs: Int = TIMEOUT_MS): Int = slots.withPermit {
        withContext(Dispatchers.IO) {
            runCatching {
                Socket().use { s ->
                    val t0 = System.nanoTime()
                    s.connect(InetSocketAddress(host, port), timeoutMs)
                    ((System.nanoTime() - t0) / 1_000_000).toInt().coerceAtLeast(1)
                }
            }.getOrDefault(-1)
        }
    }

    suspend fun pingAll(targets: List<Triple<Long, String, Int>>, probe: suspend (String, Int) -> Int): List<Pair<Long, Int>> =
        coroutineScope { targets.map { (id, h, p) -> async { id to probe(h, p) } }.awaitAll() }
}
