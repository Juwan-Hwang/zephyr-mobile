package com.zephyr.design.components

import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import com.zephyr.design.theme.ZTheme

/** "场景 ………… 2 小时前检测" row above a card. Trailing text becomes tappable when [onTrailing] is set. */
@Composable
fun ZSectionHeader(title: String, modifier: Modifier = Modifier, trailing: String? = null, onTrailing: (() -> Unit)? = null) {
    val c = ZTheme.colors
    Row(
        modifier.fillMaxWidth().padding(horizontal = 22.dp, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        ZText(title, Modifier.semantics { heading() }, style = ZTheme.type.sectionLabel, color = c.text2)
        Spacer(Modifier.weight(1f))
        if (trailing != null) {
            val m = if (onTrailing != null) Modifier.zPressable(onClick = onTrailing) else Modifier
            ZText(trailing + if (onTrailing != null) " ›" else "", m, style = ZTheme.type.footnote, color = c.text3)
        }
    }
}
