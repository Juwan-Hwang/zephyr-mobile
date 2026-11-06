package com.zephyr.design.components

import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.togetherWith
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.TextStyle
import com.zephyr.design.theme.ZAnim
import com.zephyr.design.theme.ZTheme
import com.zephyr.design.theme.latency

/** Latency readout: "152 ms" / "—" untested / "···" testing / "超时". Cross-fades on change. */
@Composable
fun ZLatency(ms: Int?, testing: Boolean = false, modifier: Modifier = Modifier, style: TextStyle = ZTheme.type.numeric) {
    val c = ZTheme.colors
    AnimatedContent(
        targetState = if (testing) Int.MIN_VALUE else ms,
        transitionSpec = { fadeIn(ZAnim.standard()) togetherWith fadeOut(ZAnim.micro()) },
        label = "latency",
        modifier = modifier,
    ) { v ->
        when {
            v == Int.MIN_VALUE -> ZText("···", style = style, color = c.text3)
            v == null -> ZText("—", style = style, color = c.text3)
            v < 0 -> ZText("超时", style = style, color = c.danger)
            else -> ZText("$v ms", style = style, color = c.latency(v))
        }
    }
}
