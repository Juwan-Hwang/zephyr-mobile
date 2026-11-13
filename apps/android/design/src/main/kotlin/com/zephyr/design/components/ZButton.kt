package com.zephyr.design.components

import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.sp
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.padding
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.unit.dp
import com.zephyr.design.theme.ZTheme

enum class ZButtonKind { Primary, Secondary, Ghost, Danger, Accent }

/** Compact = prototype `.btn` (40 visual, 14/500); Large = onboarding footer `.ob .foot .btn` (52, 16). */
enum class ZButtonSize { Compact, Large }

/**
 * Pill button. Primary = t1 pill (prototype `.btn.p`), Secondary = `--hl` fill without a border (`.btn.q`).
 * Review D-P2-4: visual height follows the prototype (40 compact / 52 large) while the touch target stays ≥ 48 dp.
 */
@Composable
fun ZButton(
    text: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    kind: ZButtonKind = ZButtonKind.Primary,
    enabled: Boolean = true,
    size: ZButtonSize = ZButtonSize.Compact,
) {
    val c = ZTheme.colors
    val (bg, fg) = when (kind) {
        ZButtonKind.Primary -> c.primaryButton to c.onPrimaryButton
        ZButtonKind.Secondary -> c.hairline to c.text1
        ZButtonKind.Ghost -> c.bg.copy(alpha = 0f) to c.accent
        ZButtonKind.Danger -> c.danger.copy(alpha = 0.14f) to c.danger
        ZButtonKind.Accent -> c.accent to c.onAccent
    }
    val shape = ZTheme.shapes.pill
    val large = size == ZButtonSize.Large
    Box(
        modifier
            .defaultMinSize(minHeight = if (large) 52.dp else 48.dp)
            .alpha(if (enabled) 1f else 0.4f)
            .zPressable(enabled = enabled, onClick = onClick),
        contentAlignment = Alignment.Center,
    ) {
        Box(
            Modifier
                .fillMaxWidth()
                .height(if (large) 52.dp else 40.dp)
                .clip(shape)
                .background(bg, shape)
                .padding(horizontal = if (large) 22.dp else 18.dp),
            contentAlignment = Alignment.Center,
        ) {
            val style = if (large) ZTheme.type.button.copy(fontSize = 16.sp)
            else ZTheme.type.button.copy(fontSize = 14.sp, fontWeight = FontWeight.Medium)
            ZText(text, style = style, color = fg, maxLines = 1)
        }
    }
}
