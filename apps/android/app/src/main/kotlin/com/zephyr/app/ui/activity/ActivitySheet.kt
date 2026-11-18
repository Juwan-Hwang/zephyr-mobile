package com.zephyr.app.ui.activity

import androidx.compose.ui.platform.LocalResources
import com.zephyr.app.ui.common.sceneName
import com.zephyr.app.R
import com.zephyr.app.ui.common.UiText
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
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.zephyr.app.di.AppGraph
import kotlinx.coroutines.launch
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
fun BoxScope.ActivitySheet(
    visible: Boolean, onDismiss: () -> Unit, trace: String? = null, onNotice: (UiText) -> Unit = {},
    onUndoable: (UiText, suspend () -> Unit) -> Unit = { m, _ -> onNotice(m) }, onHost: (String?) -> Unit,
) {
    val scope = androidx.compose.runtime.rememberCoroutineScope()
    val flow = remember { AppGraph.engine.recentHosts(5) }
    val hosts by flow.collectWhile(visible, emptyList())
    val c = ZTheme.colors
    // Review H-P2-9: like the prototype, tapping a host turns this same sheet into its trace (one scrim, one sheet);
    // back / "‹ 最近连接" returns to the list, "完成" or the scrim closes everything.
    val title = stringResource(R.string.activity_title)
    ZSheet(visible, onDismiss, if (trace == null) title else "") {
        if (trace != null) {
            androidx.activity.compose.BackHandler { onHost(null) }
            ZText(
                stringResource(R.string.activity_back),
                Modifier.padding(start = 10.dp).zPressable(label = stringResource(R.string.common_back_to, title)) { onHost(null) }.padding(horizontal = 12.dp, vertical = 8.dp),
                style = ZTheme.type.body, color = c.accent,
            )
            TraceBody(trace, onApplied = onUndoable)
            return@ZSheet
        }
        if (hosts.isEmpty()) {
            ZText(stringResource(R.string.activity_empty), Modifier.padding(22.dp), style = ZTheme.type.footnote, color = c.text3)
            return@ZSheet
        }
        ZListGroup {
            hosts.forEachIndexed { i, x ->
                if (i > 0) ZDivider()
                Row(
                    Modifier.fillMaxWidth().zPressable(
                        row = true,
                        label = stringResource(R.string.activity_host_a11y, x.host), longClickLabel = stringResource(R.string.activity_close_host_a11y, x.host),
                        // iOS H-P2-14 parity: long-press closes this host's live connections and says how it went.
                        onLongClick = { scope.launch { onNotice(closeHostConnections(AppGraph.engine, x.host)) } },
                    ) { onHost(x.host) }.padding(horizontal = 20.dp, vertical = 14.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Column(Modifier.weight(1f)) {
                        ZText(x.host, style = ZTheme.type.headline.copy(fontWeight = ZTheme.type.body.fontWeight), maxLines = 1)
                        ZText(
                            if (x.scene == null) stringResource(R.string.common_direct) else listOfNotNull(x.app, x.scene?.let { LocalResources.current.sceneName(it) }, x.node).joinToString(" · "),
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
            ZText(stringResource(R.string.activity_no_app_note), Modifier.padding(horizontal = 22.dp, vertical = 12.dp), style = ZTheme.type.footnote, color = c.text3)
        }
    }
}
