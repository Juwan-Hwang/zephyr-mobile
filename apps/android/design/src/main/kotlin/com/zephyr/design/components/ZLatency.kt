package com.zephyr.design.components

import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.togetherWith
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.text.TextStyle
import com.zephyr.design.R
import com.zephyr.design.theme.ZAnim
import com.zephyr.design.theme.ZTheme
import com.zephyr.design.theme.latency

/**
 * Latency readout: "152 ms" / "—" untested / "···" testing / "超时". Cross-fades on change.
 * TalkBack reads a phrase instead of the glyphs (audit U22, as iOS VoiceOver): "延迟 38 毫秒 / 延迟未检测 / 延迟检测中 / 延迟超时".
 */
@Composable
fun ZLatency(ms: Int?, testing: Boolean = false, modifier: Modifier = Modifier, style: TextStyle = ZTheme.type.numeric) {
    val c = ZTheme.colors
    val spoken = latencyDescription(ms, testing)
    AnimatedContent(
        targetState = if (testing) Int.MIN_VALUE else ms,
        transitionSpec = { fadeIn(ZAnim.standard()) togetherWith fadeOut(ZAnim.micro()) },
        label = "latency",
        modifier = modifier.clearAndSetSemantics { contentDescription = spoken },
    ) { v ->
        when {
            v == Int.MIN_VALUE -> ZText("···", style = style, color = c.text3)
            v == null -> ZText("—", style = style, color = c.text3)
            v < 0 -> ZText(stringResource(R.string.common_latency_timeout), style = style, color = c.latencyTimeout)
            else -> ZText("$v ms", style = style, color = c.latency(v))
        }
    }
}

/** Spoken form of a latency reading (audit U22); also used by rows that merge their children into one node. */
@Composable
fun latencyDescription(ms: Int?, testing: Boolean = false): String = when {
    testing -> stringResource(R.string.common_latency_a11y_testing)
    ms == null -> stringResource(R.string.common_latency_a11y_untested)
    ms < 0 -> stringResource(R.string.common_latency_a11y_timeout)
    else -> pluralStringResource(R.plurals.common_latency_a11y_ms, ms, ms)
}
