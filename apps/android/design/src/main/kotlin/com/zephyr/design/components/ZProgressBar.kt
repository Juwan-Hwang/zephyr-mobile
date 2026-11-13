package com.zephyr.design.components

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.ProgressBarRangeInfo
import androidx.compose.ui.semantics.progressBarRangeInfo
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import com.zephyr.design.theme.ZAnim
import com.zephyr.design.theme.ZTheme

/** 2dp usage bar (subscription traffic). */
@Composable
fun ZProgressBar(progress: Float, modifier: Modifier = Modifier, color: Color = ZTheme.colors.text2) {
    val p by animateFloatAsState(progress.coerceIn(0f, 1f), ZAnim.slow(), label = "progress")
    Box(
        modifier
            .fillMaxWidth()
            .height(2.dp)
            .clip(ZTheme.shapes.pill)
            .background(ZTheme.colors.hairline)
            .semantics { progressBarRangeInfo = ProgressBarRangeInfo(p, 0f..1f) },
    ) {
        Box(Modifier.fillMaxHeight().fillMaxWidth(p).clip(ZTheme.shapes.pill).background(color))
    }
}
