package com.zephyr.app.ui.nav

import org.junit.Assert.assertEquals
import org.junit.Test

/** #208 back motion: predictive back tracks the finger from the swiped edge; the page below moves a quarter width. */
class NavMotionTest {
    @Test fun swipeEdgeDecidesDirection() {
        assertEquals(1, NavMotion.exitSign(NavMotion.EDGE_LEFT, layoutSign = 1))
        assertEquals(-1, NavMotion.exitSign(NavMotion.EDGE_RIGHT, layoutSign = 1))
        // A swipe is physical: the same in RTL.
        assertEquals(1, NavMotion.exitSign(NavMotion.EDGE_LEFT, layoutSign = -1))
        assertEquals(-1, NavMotion.exitSign(NavMotion.EDGE_RIGHT, layoutSign = -1))
        // Link / no edge: back toward the end edge, mirrored in RTL.
        assertEquals(1, NavMotion.exitSign(NavMotion.EDGE_NONE, layoutSign = 1))
        assertEquals(-1, NavMotion.exitSign(NavMotion.EDGE_NONE, layoutSign = -1))
    }

    @Test fun topLeavesFullWidthUnderMovesParallax() {
        assertEquals(1080, NavMotion.topOffset(1080, 1))
        assertEquals(-1080, NavMotion.topOffset(1080, -1))
        assertEquals(-270, NavMotion.underOffset(1080, 1))
        assertEquals(270, NavMotion.underOffset(1080, -1))
    }

    @Test fun gestureProgressMapsLinearlyAndClamps() {
        assertEquals(0, NavMotion.trackedOffset(0f, 1080, 1))
        assertEquals(270, NavMotion.trackedOffset(0.25f, 1080, 1))
        assertEquals(-540, NavMotion.trackedOffset(0.5f, 1080, -1))
        assertEquals(1080, NavMotion.trackedOffset(1.4f, 1080, 1))
        assertEquals(0, NavMotion.trackedOffset(-0.2f, 1080, 1))
    }
}
