package com.zephyr.app.widget

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** And-8 / CodeAnt #285: optional widget lines are budgeted from cell height and font scale. */
class WidgetFitTest {
    @Test fun defaultScaleMatchesSnapshotLayouts() {
        assertEquals(WidgetFit(detail = true, today = false, sceneRows = 2), ZephyrWidget.widgetFit(110f, 1f))
        assertEquals(WidgetFit(detail = true, today = true, sceneRows = 3), ZephyrWidget.widgetFit(150f, 1f))
    }

    @Test fun largeFontDropsDetailInSmallCell() {
        val f = ZephyrWidget.widgetFit(110f, 1.5f)
        assertFalse(f.detail); assertFalse(f.today)
        assertTrue(f.sceneRows <= 1)
    }

    @Test fun largeFontDropsTodayBeforeDetailInTallCell() {
        val f = ZephyrWidget.widgetFit(150f, 1.3f)
        assertTrue(f.detail); assertFalse(f.today)
    }
}
