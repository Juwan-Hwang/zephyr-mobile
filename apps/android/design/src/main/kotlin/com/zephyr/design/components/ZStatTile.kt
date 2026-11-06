package com.zephyr.design.components

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.zephyr.design.theme.ZTheme

/** Library tile: thin big number over a label ("1,311 万 / 节点"). */
@Composable
fun ZStatTile(value: String, label: String, modifier: Modifier = Modifier, onClick: (() -> Unit)? = null) {
    ZSurface(modifier.then(if (onClick != null) Modifier.zPressable(onClick = onClick) else Modifier), shape = ZTheme.shapes.card) {
        Column(Modifier.padding(horizontal = 18.dp, vertical = 18.dp)) {
            ZText(value, style = ZTheme.type.number, maxLines = 1)
            Spacer(Modifier.height(14.dp))
            ZText(label, style = ZTheme.type.callout, color = ZTheme.colors.text2)
        }
    }
}
