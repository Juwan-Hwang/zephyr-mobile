package com.zephyr.app.ui.home

import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Popup
import androidx.compose.ui.window.PopupProperties
import com.zephyr.app.ui.common.ZephyrLockup
import com.zephyr.design.components.ZIcon
import com.zephyr.design.components.ZIconButton
import com.zephyr.design.components.ZIcons
import com.zephyr.design.components.ZSurface
import com.zephyr.design.components.ZSurfaceStyle
import com.zephyr.design.components.ZText
import com.zephyr.design.components.ZToggle
import com.zephyr.design.components.ZToggleSize
import com.zephyr.design.components.zPressable
import com.zephyr.design.format.ZFormat
import com.zephyr.design.theme.ZAnim
import com.zephyr.design.theme.ZTheme
import com.zephyr.engine.ConnectionState
import com.zephyr.engine.ConnectionStatus
import com.zephyr.engine.ProxyMode

@Composable
fun HomeTopBar(status: ConnectionStatus, onSettings: () -> Unit) {
    val c = ZTheme.colors
    val dot by animateColorAsState(if (status == ConnectionStatus.CONNECTED) c.connected else c.text4, ZAnim.standard(), label = "dot")
    Row(Modifier.fillMaxWidth().padding(start = 22.dp, end = 8.dp), verticalAlignment = Alignment.CenterVertically) {
        Box(
            Modifier.size(16.dp).drawBehind {
                if (status == ConnectionStatus.CONNECTED) drawCircle(dot.copy(alpha = 0.22f), radius = size.minDimension / 2)
                drawCircle(dot, radius = size.minDimension / 4)
            },
        )
        Spacer(Modifier.width(6.dp))
        ZephyrLockup()
        Spacer(Modifier.weight(1f))
        ZIconButton(ZIcons.Settings, "设置", onSettings, tint = c.text2)
    }
}

/** "已连接" + hero switch, then "规则 ⌄  2:14:07". */
@Composable
fun HomeStatus(
    connection: ConnectionState,
    now: Long,
    sceneCount: Int,
    onToggle: (Boolean) -> Unit,
    onMode: (ProxyMode) -> Unit,
) {
    val c = ZTheme.colors
    val on = connection.status == ConnectionStatus.CONNECTED || connection.status == ConnectionStatus.CONNECTING
    Column(Modifier.fillMaxWidth().padding(horizontal = 22.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            AnimatedContent(
                targetState = connection.status,
                transitionSpec = { fadeIn(ZAnim.standard()) togetherWith fadeOut(ZAnim.micro()) },
                label = "status",
                modifier = Modifier.weight(1f).semantics { liveRegion = LiveRegionMode.Polite },
            ) { s ->
                ZText(
                    when (s) {
                        ConnectionStatus.CONNECTED -> "已连接"
                        ConnectionStatus.CONNECTING -> "正在连接"
                        ConnectionStatus.DISCONNECTING -> "正在断开"
                        ConnectionStatus.FAILED -> "连接失败"
                        ConnectionStatus.DISCONNECTED -> "未连接"
                    },
                    style = ZTheme.type.status,
                    maxLines = 1,
                )
            }
            ZToggle(on, onToggle, size = ZToggleSize.Hero, contentDescription = "连接")
        }
        Spacer(Modifier.height(10.dp))
        Row(verticalAlignment = Alignment.CenterVertically) {
            ModePicker(connection.mode, onMode)
            Spacer(Modifier.width(18.dp))
            val since = connection.since
            ZText(
                when {
                    connection.status == ConnectionStatus.FAILED -> failureText(connection.error?.code)
                    connection.status == ConnectionStatus.CONNECTED && since != null -> ZFormat.duration(now - since)
                    else -> "$sceneCount 个场景"
                },
                style = ZTheme.type.numeric.copy(fontSize = ZTheme.type.headline.fontSize),
                color = c.text3,
            )
        }
    }
}

@Composable
private fun ModePicker(mode: ProxyMode, onMode: (ProxyMode) -> Unit) {
    val c = ZTheme.colors
    var open by remember { mutableStateOf(false) }
    val rot by animateFloatAsState(if (open) 180f else 0f, ZAnim.standard(), label = "chev")
    Box {
        Row(Modifier.zPressable(label = "切换模式") { open = true }.padding(vertical = 6.dp), verticalAlignment = Alignment.CenterVertically) {
            ZText(mode.label, style = ZTheme.type.headline.copy(fontWeight = ZTheme.type.bodyStrong.fontWeight))
            Spacer(Modifier.width(4.dp))
            ZIcon(ZIcons.ChevronDown, Modifier.then(Modifier), tint = c.text2, size = 16.dp)
        }
        if (open) {
            Popup(onDismissRequest = { open = false }, properties = PopupProperties(focusable = true)) {
                ZSurface(Modifier.padding(top = 36.dp).width(200.dp), style = ZSurfaceStyle.Raised, shape = ZTheme.shapes.surface) {
                    Column(Modifier.padding(vertical = 6.dp)) {
                        ProxyMode.entries.forEach { m ->
                            Row(
                                Modifier.fillMaxWidth().zPressable(haptic = m != mode) { open = false; onMode(m) }.padding(horizontal = 16.dp, vertical = 12.dp),
                                verticalAlignment = Alignment.CenterVertically,
                            ) {
                                Column(Modifier.weight(1f)) {
                                    ZText(m.label, style = ZTheme.type.body)
                                    ZText(m.hint, style = ZTheme.type.caption, color = c.text3)
                                }
                                if (m == mode) ZIcon(ZIcons.Check, tint = c.accent, size = 18.dp)
                            }
                        }
                    }
                }
            }
        }
    }
}

val ProxyMode.label: String get() = when (this) { ProxyMode.RULE -> "规则"; ProxyMode.GLOBAL -> "全局"; ProxyMode.DIRECT -> "直连" }
val ProxyMode.hint: String get() = when (this) {
    ProxyMode.RULE -> "按场景分流"
    ProxyMode.GLOBAL -> "所有流量经由一个节点"
    ProxyMode.DIRECT -> "不经过代理"
}


/** One line under "连接失败": what to do next, never a raw error. */
internal fun failureText(code: com.zephyr.engine.ErrorCode?): String = when (code) {
    com.zephyr.engine.ErrorCode.SUBSCRIPTION_NOT_FOUND -> "先添加一个订阅"
    com.zephyr.engine.ErrorCode.VPN_PERMISSION_DENIED -> "需要允许 VPN 连接"
    com.zephyr.engine.ErrorCode.NETWORK_UNAVAILABLE -> "网络不可用"
    else -> "内核未能启动"
}
