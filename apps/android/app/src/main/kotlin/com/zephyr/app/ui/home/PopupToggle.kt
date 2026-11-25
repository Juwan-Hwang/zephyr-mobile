package com.zephyr.app.ui.home

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue

/**
 * Open state of a trigger + focusable `Popup` pair (Home 规则 ⌄ mode panel). Issue #1 (real device): with the panel
 * open, a tap on the same trigger first reaches the popup as an outside touch ([dismiss], on pointer down) and then
 * the trigger's click ([toggle], on pointer up), which reopened it at once. A [toggle] within [SAME_GESTURE_MS] of an
 * outside dismiss is that same tap, so it leaves the panel closed. Pure state; [clock] is a test seam.
 */
internal class PopupToggle(private val clock: () -> Long = { android.os.SystemClock.uptimeMillis() }) {
    var open by mutableStateOf(false)
        private set

    /** 0 = never dismissed by an outside touch. */
    private var dismissedAt = 0L

    /** The trigger was tapped. */
    fun toggle() {
        if (open) { open = false; return }
        if (dismissedAt != 0L && clock() - dismissedAt < SAME_GESTURE_MS) return
        open = true
    }

    /** `onDismissRequest`: a touch outside the popup (possibly on the trigger) or back. */
    fun dismiss() {
        if (!open) return
        open = false
        dismissedAt = clock()
    }

    /** An item in the panel was chosen. */
    fun close() { open = false }

    companion object {
        /** Longer than a tap's down → up; shorter than a deliberate second tap. */
        const val SAME_GESTURE_MS = 500L
    }
}
