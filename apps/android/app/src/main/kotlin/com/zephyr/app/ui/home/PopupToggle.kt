package com.zephyr.app.ui.home

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.IntRect
import androidx.compose.ui.unit.IntSize
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.window.PopupPositionProvider

/**
 * Open state of a trigger + focusable `Popup` pair (Home 规则 ⌄ mode panel). Issue #1 (real device): with the panel
 * open, a tap on the same trigger first reaches the popup as an outside touch ([dismiss], on pointer down) and then
 * the trigger's click ([toggle], on pointer up), which reopened it at once. A [toggle] within [SAME_GESTURE_MS] of an
 * outside dismiss is that same tap, so it leaves the panel closed. Pure state; [clock] is a test seam.
 *
 * This only works if the popup window does not cover the trigger: a tap that lands inside the popup (even on its
 * transparent padding) is neither an outside touch nor a trigger click. Place the popup with [BelowAnchor].
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

/**
 * Issue #1 (S25 Ultra, after #324): the popups used to sit at the anchor's top and push their surface down with
 * `Modifier.padding(top = …)` inside the popup, so the popup window's transparent top strip covered the trigger and a
 * second tap on it went to the popup, not to the trigger nor to `onDismissRequest`. This places the popup window
 * itself [minTop] px below the anchor's top (never less than the anchor's height, so it can't overlap the anchor),
 * start-aligned (or end-aligned with [endInset] px inset when [alignEnd]), mirrored in RTL.
 */
internal class BelowAnchor(
    private val minTop: Int,
    private val alignEnd: Boolean = false,
    private val endInset: Int = 0,
) : PopupPositionProvider {
    override fun calculatePosition(
        anchorBounds: IntRect,
        windowSize: IntSize,
        layoutDirection: LayoutDirection,
        popupContentSize: IntSize,
    ): IntOffset {
        val y = anchorBounds.top + maxOf(minTop, anchorBounds.height)
        val rightEdge = (layoutDirection == LayoutDirection.Ltr) == alignEnd
        val x = if (rightEdge) {
            anchorBounds.right - popupContentSize.width - (if (alignEnd) endInset else 0)
        } else {
            anchorBounds.left + (if (alignEnd) endInset else 0)
        }
        return IntOffset(x, y)
    }
}
