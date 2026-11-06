package com.zephyr.design.components

import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.unit.dp
import com.zephyr.design.format.ZFormat
import com.zephyr.design.theme.ZTheme

/** "2.8 MB/s ↓  /  195 KB/s ↑" — thin hero digits, each digit rolls when it changes. */
@Composable
fun ZTrafficStat(downBps: Long, upBps: Long, modifier: Modifier = Modifier) {
    val c = ZTheme.colors
    val (dv, du) = ZFormat.rate(downBps)
    val (uv, uu) = ZFormat.rate(upBps)
    Column(modifier.clearAndSetSemantics { contentDescription = "下载 $dv $du 每秒，上传 $uv $uu 每秒" }) {
        Row(verticalAlignment = Alignment.Bottom) {
            RollingNumber(dv)
            Spacer(Modifier.width(10.dp))
            ZText("$du/s", Modifier.padding(bottom = 8.dp), style = ZTheme.type.headline.copy(fontWeight = ZTheme.type.body.fontWeight), color = c.text3)
            Spacer(Modifier.width(4.dp))
            ZIcon(ZIcons.ArrowDown, Modifier.padding(bottom = 10.dp), tint = c.download, size = 18.dp)
        }
        Row(verticalAlignment = Alignment.CenterVertically) {
            ZText("$uv $uu/s", style = ZTheme.type.numeric.copy(fontSize = ZTheme.type.headline.fontSize), color = c.text2)
            Spacer(Modifier.width(4.dp))
            ZIcon(ZIcons.ArrowUp, tint = c.upload, size = 16.dp)
        }
    }
}

@Composable
private fun RollingNumber(text: String) {
    Row {
        text.forEachIndexed { i, ch ->
            AnimatedContent(
                targetState = ch,
                transitionSpec = {
                    val up = targetState > initialState
                    (slideInVertically(tween(260)) { if (up) it / 2 else -it / 2 } + fadeIn(tween(260))) togetherWith
                        (slideOutVertically(tween(200)) { if (up) -it / 2 else it / 2 } + fadeOut(tween(160)))
                },
                label = "digit$i",
            ) { c -> ZText(c.toString(), style = ZTheme.type.hero) }
        }
    }
}
