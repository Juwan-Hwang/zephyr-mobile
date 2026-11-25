package com.zephyr.app.ui.home

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** Issue #1 (real device): a second tap on 规则 ⌄ closes the panel instead of reopening it. */
class PopupToggleTest {
    private var now = 10_000L
    private val t = PopupToggle { now }

    @Test fun tapOpensTapAgainCloses() {
        t.toggle(); assertTrue(t.open)
        // the same tap: outside-touch dismiss on down, then the trigger's click on up
        t.dismiss(); now += 120; t.toggle()
        assertFalse(t.open)
    }

    @Test fun laterTapReopens() {
        t.toggle(); t.dismiss()
        now += PopupToggle.SAME_GESTURE_MS + 1; t.toggle()
        assertTrue(t.open)
    }

    @Test fun choosingAnItemDoesNotBlockTheNextTap() {
        t.toggle(); t.close(); now += 50; t.toggle()
        assertTrue(t.open)
    }

    @Test fun toggleWhileOpenWithoutDismissCloses() {
        t.toggle(); t.toggle(); assertFalse(t.open)
    }
}
