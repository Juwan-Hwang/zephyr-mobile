package com.zephyr.app.ui.common

import androidx.compose.runtime.Composable
import androidx.compose.runtime.State
import androidx.compose.runtime.produceState
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.repeatOnLifecycle
import kotlinx.coroutines.flow.Flow

/**
 * Collects only while [active] (a sheet is open) and the app is at least STARTED; keeps the last value when it
 * stops, so a closing sheet animates out with its content instead of flashing empty. Hidden sheets stay in
 * composition for their animations but must not poll the core (review H-P1-6).
 */
@Composable
fun <T> Flow<T>.collectWhile(active: Boolean, initial: T): State<T> {
    val owner = LocalLifecycleOwner.current
    return produceState(initial, this, active, owner) {
        if (active) owner.repeatOnLifecycle(Lifecycle.State.STARTED) { collect { value = it } }
    }
}
