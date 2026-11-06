package com.zephyr.design.components

import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.padding
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.zephyr.design.theme.ZTheme

/**
 * Region code chip ("SG", "HK"): monospaced letters in a hairline box — the prototype replaces emoji flags
 * (which render inconsistently and are politically sensitive for some regions) with ISO codes.
 */
@Composable
fun ZRegionBadge(code: String, modifier: Modifier = Modifier, large: Boolean = false) {
    val c = ZTheme.colors
    Box(
        modifier
            .defaultMinSize(minWidth = if (large) 40.dp else 32.dp)
            .border(1.dp, c.hairlineStrong, ZTheme.shapes.control)
            .padding(horizontal = 6.dp, vertical = if (large) 5.dp else 3.dp),
        contentAlignment = Alignment.Center,
    ) {
        ZText(code.uppercase(), style = if (large) ZTheme.type.mono else ZTheme.type.monoSmall, color = c.text2, maxLines = 1)
    }
}
