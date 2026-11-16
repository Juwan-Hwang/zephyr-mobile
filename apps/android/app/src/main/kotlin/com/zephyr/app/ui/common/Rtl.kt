package com.zephyr.app.ui.common

import androidx.compose.runtime.Composable
import androidx.compose.runtime.ReadOnlyComposable
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.unit.LayoutDirection

/**
 * +1 in left-to-right layouts, -1 in right-to-left ones (ar, fa, ur). Multiply raw x values that Compose does not
 * mirror on its own — graphicsLayer translationX, slideIn/OutHorizontally offsets, pointer deltas, Canvas x — so
 * motion keeps meaning "toward the end edge" / "back toward the start edge" in both directions.
 * Layout (padding/offset/Arrangement/Alignment start-end) already mirrors and must not be multiplied.
 */
@Composable
@ReadOnlyComposable
fun startToEndSign(): Int = if (LocalLayoutDirection.current == LayoutDirection.Rtl) -1 else 1
