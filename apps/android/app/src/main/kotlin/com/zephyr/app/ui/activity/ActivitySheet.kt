package com.zephyr.app.ui.activity

import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.zephyr.app.di.AppGraph
import com.zephyr.design.components.ZDivider
import com.zephyr.design.components.ZListGroup
import com.zephyr.design.components.ZSheet
import com.zephyr.design.components.ZText
import com.zephyr.design.format.ZFormat
import com.zephyr.design.theme.ZTheme

/** Recent connections (prototype `actSheet`). Android can attribute apps; shown when the core reports it. */
@Composable
fun BoxScope.ActivitySheet(visible: Boolean, onDismiss: () -> Unit) {
    val conns by AppGraph.engine.activeConnections().collectAsState(emptyList())
    val c = ZTheme.colors
    ZSheet(visible, onDismiss, "最近连接") {
        if (conns.isEmpty()) {
            ZText("连接后这里会显示正在进行的连接。", Modifier.padding(22.dp), style = ZTheme.type.footnote, color = c.text3)
            return@ZSheet
        }
        ZListGroup {
            conns.take(12).forEachIndexed { i, x ->
                if (i > 0) ZDivider()
                Row(Modifier.fillMaxWidth().padding(horizontal = 20.dp, vertical = 12.dp), verticalAlignment = Alignment.CenterVertically) {
                    Column(Modifier.weight(1f)) {
                        ZText(x.host, style = ZTheme.type.mono, maxLines = 1)
                        ZText(listOfNotNull(x.app, x.scene, x.node).joinToString(" · "), style = ZTheme.type.footnote, color = c.text3, maxLines = 1)
                    }
                    ZText(ZFormat.bytesText(x.downBytes + x.upBytes), style = ZTheme.type.monoSmall, color = c.text2)
                }
            }
        }
    }
}
