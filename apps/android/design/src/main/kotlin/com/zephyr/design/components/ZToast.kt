package com.zephyr.design.components

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import com.zephyr.design.theme.ZAnim
import com.zephyr.design.theme.ZTheme

/** "已换到 东京 03 · 撤销" glass toast; caller owns the 4 s window (tokens motion.undo-window). */
@Composable
fun ZToast(visible: Boolean, message: String, modifier: Modifier = Modifier, action: String? = null, onAction: (() -> Unit)? = null) {
    AnimatedVisibility(
        visible,
        modifier,
        enter = fadeIn(ZAnim.standard()) + slideInVertically(ZAnim.slow()) { it / 2 },
        exit = fadeOut(ZAnim.standard()) + slideOutVertically(ZAnim.standard()) { it / 2 },
    ) {
        ZSurface(style = ZSurfaceStyle.Glass, shape = ZTheme.shapes.pill) {
            Row(
                Modifier.padding(horizontal = 20.dp, vertical = 12.dp).semantics { liveRegion = LiveRegionMode.Polite },
                verticalAlignment = Alignment.CenterVertically,
            ) {
                ZText(message, style = ZTheme.type.callout, maxLines = 1)
                if (action != null && onAction != null) {
                    Spacer(Modifier.width(16.dp))
                    ZText(action, Modifier.zPressable(onClick = onAction), style = ZTheme.type.button, color = ZTheme.colors.accent)
                }
            }
        }
    }
}
