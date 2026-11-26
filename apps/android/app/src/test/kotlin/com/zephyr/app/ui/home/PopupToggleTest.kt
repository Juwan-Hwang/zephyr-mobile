package com.zephyr.app.ui.home

import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.IntRect
import androidx.compose.ui.unit.IntSize
import androidx.compose.ui.unit.LayoutDirection
import org.junit.Assert.assertEquals
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

/** Issue #1 (S25 Ultra, after #324): the popup window must start below the trigger, never over it. */
class BelowAnchorTest {
    private val window = IntSize(1440, 3120)
    private val panel = IntSize(600, 900)

    @Test fun modePanelStartsBelowTheTrigger() {
        val trigger = IntRect(left = 48, top = 300, right = 248, bottom = 396) // 96 px tall trigger
        val p = BelowAnchor(minTop = 108).calculatePosition(trigger, window, LayoutDirection.Ltr, panel)
        assertEquals(IntOffset(48, 408), p)
        assertTrue("popup overlaps the trigger", p.y >= trigger.bottom)
    }

    @Test fun neverOverlapsATallerAnchor() {
        val row = IntRect(0, 1000, 1440, 1240) // a two-line settings row taller than minTop
        val p = BelowAnchor(minTop = 144, alignEnd = true, endInset = 48).calculatePosition(row, window, LayoutDirection.Ltr, panel)
        assertEquals(IntOffset(1440 - 600 - 48, 1240), p)
    }

    @Test fun mirrorsInRtl() {
        val trigger = IntRect(1192, 300, 1392, 396)
        assertEquals(IntOffset(1392 - 600, 408), BelowAnchor(108).calculatePosition(trigger, window, LayoutDirection.Rtl, panel))
        val row = IntRect(0, 1000, 1440, 1144)
        assertEquals(IntOffset(48, 1144), BelowAnchor(144, alignEnd = true, endInset = 48).calculatePosition(row, window, LayoutDirection.Rtl, panel))
    }
}
