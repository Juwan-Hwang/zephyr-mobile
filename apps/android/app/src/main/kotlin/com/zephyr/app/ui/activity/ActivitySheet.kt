package com.zephyr.app.ui.activity

import com.zephyr.app.ui.common.collectWhile
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.zephyr.app.di.AppGraph
import com.zephyr.design.components.ZDivider
import com.zephyr.design.components.ZIcon
import com.zephyr.design.components.ZIcons
import com.zephyr.design.components.ZListGroup
import com.zephyr.design.components.ZSheet
import com.zephyr.design.components.ZText
import com.zephyr.design.components.zPressable
import com.zephyr.design.format.ZFormat
import com.zephyr.design.theme.ZTheme

/** "最近连接" (prototype `actSheet`): recent hosts aggregated by domain; tap → trace. Android can name the app. */
@Composable
fun BoxScope.ActivitySheet(visible: Boolean, onDismiss: () -> Unit, trace: String? = null, onHost: (String?) -> Unit) {
    val flow = remember { AppGraph.engine.recentHosts(5) }
    val hosts by flow.collectWhile(visible, emptyList())
    val c = ZTheme.colors
    // Review H-P2-9: like the prototype, tapping a host turns this same sheet into its trace (one scrim, one sheet);
    // back / "‹ 最近连接" returns to the list, "完成" or the scrim closes everything.
    ZSheet(visible, onDismiss, if (trace == null) "最近连接" else "") {
        if (trace != null) {
            androidx.activity.compose.BackHandler { onHost(null) }
            ZText(
                "‹ 最近连接",
                Modifier.padding(start = 10.dp).zPressable(label = "返回最近连接") { onHost(null) }.padding(horizontal = 12.dp, vertical = 8.dp),
                style = ZTheme.type.body, color = c.accent,
            )
            TraceBody(trace)
            return@ZSheet
        }
        if (hosts.isEmpty()) {
            ZText("连接后这里会显示最近访问的域名。", Modifier.padding(22.dp), style = ZTheme.type.footnote, color = c.text3)
            return@ZSheet
        }
        ZListGroup {
            hosts.forEachIndexed { i, x ->
                if (i > 0) ZDivider()
                Row(
                    Modifier.fillMaxWidth().zPressable(label = "${x.host} 连接详情") { onHost(x.host) }.padding(horizontal = 20.dp, vertical = 14.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Column(Modifier.weight(1f)) {
                        ZText(x.host, style = ZTheme.type.headline.copy(fontWeight = ZTheme.type.body.fontWeight), maxLines = 1)
                        ZText(
                            if (x.scene == null) "直连" else listOfNotNull(x.app, x.scene, x.node).joinToString(" · "),
                            style = ZTheme.type.callout, color = c.text3, maxLines = 1,
                        )
                    }
                    ZText(ZFormat.bytesText(x.downBytes + x.upBytes), style = ZTheme.type.mono, color = c.text2)
                    Spacer(Modifier.width(10.dp))
                    ZIcon(ZIcons.ChevronRight, tint = c.text4, size = 16.dp)
                }
            }
        }
        if (hosts.all { it.app == null }) {
            ZText("暂未取得发起连接的应用，只显示域名。", Modifier.padding(horizontal = 22.dp, vertical = 12.dp), style = ZTheme.type.footnote, color = c.text3)
        }
    }
}
