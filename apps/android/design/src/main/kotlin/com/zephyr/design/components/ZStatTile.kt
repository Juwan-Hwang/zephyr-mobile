package com.zephyr.design.components

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicText
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.zephyr.design.theme.ZTheme

/**
 * Library tile: thin big number over a label ("1,311 万 / 节点").
 * Review L-P2-1: prototype `.lc` — 110 tall, number top / label bottom, number 200 30px, label 14px, radius 20.
 * The number shrinks to fit one line instead of ellipsizing at large font scales.
 */
@Composable
fun ZStatTile(value: String, label: String, modifier: Modifier = Modifier, onClick: (() -> Unit)? = null) {
    ZSurface(modifier.then(if (onClick != null) Modifier.zPressable(onClick = onClick) else Modifier), shape = RoundedCornerShape(20.dp)) {
        Column(Modifier.heightIn(min = 110.dp).padding(horizontal = 18.dp, vertical = 16.dp), verticalArrangement = Arrangement.SpaceBetween) {
            FitText(value)
            Spacer(Modifier.height(10.dp))
            ZText(label, style = ZTheme.type.callout.copy(fontSize = 14.sp, lineHeight = 19.sp), color = ZTheme.colors.text2)
        }
    }
}

@Composable
private fun FitText(text: String) {
    val base = ZTheme.type.number
    var scale by remember(text) { mutableFloatStateOf(1f) }
    BasicText(
        text,
        Modifier,
        style = base.copy(color = ZTheme.colors.text1, fontSize = base.fontSize * scale, lineHeight = base.lineHeight * scale),
        maxLines = 1,
        softWrap = false,
        overflow = TextOverflow.Clip,
        onTextLayout = { r -> if (r.didOverflowWidth && scale > 0.5f) scale *= 0.9f },
    )
}
