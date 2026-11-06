package com.zephyr.engine.core

import com.zephyr.engine.ZephyrEngine

/**
 * Engine backed by the Rust core (core-mobile, UniFFI). Until core-mobile exports the v0 surface
 * (node index/search, rule trace, scenes, subscription diff, live stats), every call is delegated
 * to [fallback] — the contract keeps the UI oblivious to which one is running.
 *
 * Wiring plan: core-mobile publishes `uniffi/zephyr_mobile/zephyr_mobile.kt` + per-ABI `libzephyr_mobile.so`;
 * each method here then overrides the delegate one by one.
 */
class CoreEngine(private val fallback: ZephyrEngine) : ZephyrEngine by fallback {
    val isNative: Boolean get() = false
}
