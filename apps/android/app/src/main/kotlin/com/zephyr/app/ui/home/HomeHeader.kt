package com.zephyr.app.ui.home

import androidx.annotation.StringRes
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.background
import androidx.compose.foundation.text.TextAutoSize
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
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Popup
import androidx.compose.ui.window.PopupProperties
import com.zephyr.app.R
import com.zephyr.app.ui.common.LockupStyle
import com.zephyr.app.ui.common.ZephyrLockup
import com.zephyr.app.ui.common.hintRes
import com.zephyr.app.ui.common.labelRes
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
        ZephyrLockup(style = LockupStyle.Home)
        Spacer(Modifier.weight(1f))
        ZIconButton(ZIcons.Settings, stringResource(R.string.common_settings), onSettings, tint = c.text2)
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
                    stringResource(
                        when (s) {
                            ConnectionStatus.CONNECTED -> R.string.common_status_connected
                            ConnectionStatus.CONNECTING -> R.string.common_status_connecting
                            ConnectionStatus.DISCONNECTING -> R.string.common_status_disconnecting
                            ConnectionStatus.FAILED -> R.string.common_status_failed
                            ConnectionStatus.DISCONNECTED -> R.string.common_status_disconnected
                        },
                    ),
                    style = ZTheme.type.status,
                    maxLines = 1,
                    // Long translations (sw "Imeunganishwa", ru "Не удалось подключиться") step down instead of
                    // running into the switch; anything that fits renders at the full status size as before.
                    autoSize = TextAutoSize.StepBased(minFontSize = 26.sp, maxFontSize = ZTheme.type.status.fontSize),
                )
            }
            Spacer(Modifier.width(12.dp))
            ZToggle(on, onToggle, size = ZToggleSize.Hero, contentDescription = stringResource(R.string.common_connect))
        }
        Spacer(Modifier.height(10.dp))
        Row(verticalAlignment = Alignment.CenterVertically) {
            ModePicker(connection.mode, onMode)
            Spacer(Modifier.width(18.dp))
            val since = connection.since
            ZText(
                when {
                    connection.status == ConnectionStatus.FAILED -> stringResource(failureText(connection.error))
                    connection.status == ConnectionStatus.CONNECTED && since != null -> ZFormat.duration(now - since)
                    else -> pluralStringResource(R.plurals.home_scene_count, sceneCount, sceneCount)
                },
                style = ZTheme.type.numeric.copy(fontSize = 14.sp), // Review H-P2-1: prototype .sub 14px, t3
                color = c.text3,
            )
        }
        // Issue #1 (S25 Ultra): the raw reason, one line by default; tap to expand. Only while the failure shows.
        val detail = connection.error?.takeIf { connection.status == ConnectionStatus.FAILED }?.let { failureDetail(it) }
        if (detail != null) FailureDetail(detail)
    }
}

/** Expandable "why it failed" line under the failure hint (issue #1): ZephyrError.message, truncated. */
@Composable
private fun FailureDetail(detail: String) {
    val c = ZTheme.colors
    var open by remember(detail) { mutableStateOf(false) }
    val rot by animateFloatAsState(if (open) 180f else 0f, ZAnim.standard(), label = "detailChev")
    Spacer(Modifier.height(6.dp))
    Row(
        Modifier.fillMaxWidth().zPressable(label = stringResource(R.string.home_failure_details_a11y)) { open = !open }.padding(vertical = 4.dp),
        verticalAlignment = Alignment.Top,
    ) {
        ZText(
            detail,
            Modifier.weight(1f, fill = false),
            style = ZTheme.type.caption,
            color = c.text3,
            maxLines = if (open) FAILURE_DETAIL_LINES else 1,
        )
        Spacer(Modifier.width(4.dp))
        ZIcon(ZIcons.ChevronDown, Modifier.padding(top = 2.dp).graphicsLayer { rotationZ = rot }, tint = c.text3, size = 12.dp)
    }
}

/** Expanded detail line cap; longer messages are cut by [failureDetail] first. */
private const val FAILURE_DETAIL_LINES = 6
internal const val FAILURE_DETAIL_MAX_CHARS = 240

/** The error's own message, whitespace folded and cut to [FAILURE_DETAIL_MAX_CHARS]; null when there is none. */
internal fun failureDetail(e: com.zephyr.engine.ZephyrError): String? {
    val m = e.message.trim().replace(Regex("\\s+"), " ")
    if (m.isEmpty()) return null
    return if (m.length <= FAILURE_DETAIL_MAX_CHARS) m else m.take(FAILURE_DETAIL_MAX_CHARS - 1).trimEnd() + "…"
}

@Composable
private fun ModePicker(mode: ProxyMode, onMode: (ProxyMode) -> Unit) {
    val c = ZTheme.colors
    val toggle = remember { PopupToggle() }
    val open = toggle.open
    val rot by animateFloatAsState(if (open) 180f else 0f, ZAnim.standard(), label = "chev")
    Box {
        Row(Modifier.zPressable(label = stringResource(R.string.home_switch_mode)) { toggle.toggle() }.padding(vertical = 6.dp), verticalAlignment = Alignment.CenterVertically) {
            ZText(stringResource(mode.labelRes), style = ZTheme.type.bodyStrong.copy(fontSize = 14.sp, lineHeight = 20.sp))
            Spacer(Modifier.width(4.dp))
            ZIcon(ZIcons.ChevronDown, Modifier.then(Modifier), tint = c.text2, size = 14.dp)
        }
        if (open) {
            // Issue #1: the popup window starts below the trigger (no transparent padding over it), so a second tap on
            // the trigger is an outside touch → dismiss, then PopupToggle's same-gesture guard keeps it closed.
            val top = with(LocalDensity.current) { 36.dp.roundToPx() }
            Popup(popupPositionProvider = remember(top) { BelowAnchor(top) }, onDismissRequest = { toggle.dismiss() }, properties = PopupProperties(focusable = true)) {
                ZSurface(Modifier.width(200.dp), style = ZSurfaceStyle.Raised, shape = ZTheme.shapes.surface) {
                    Column(Modifier.padding(vertical = 6.dp)) {
                        ProxyMode.entries.forEach { m ->
                            Row(
                                Modifier.fillMaxWidth().zPressable(row = true, haptic = m != mode) { toggle.close(); onMode(m) }.padding(horizontal = 16.dp, vertical = 12.dp),
                                verticalAlignment = Alignment.CenterVertically,
                            ) {
                                Column(Modifier.weight(1f)) {
                                    ZText(stringResource(m.labelRes), style = ZTheme.type.body)
                                    ZText(stringResource(m.hintRes), style = ZTheme.type.caption, color = c.text3)
                                }
                                if (m == mode) ZIcon(ZIcons.Check, tint = c.accentText, size = 18.dp)
                            }
                        }
                    }
                }
            }
        }
    }
}

/** One line under "连接失败": what to do next, never a raw error (that is [failureDetail]'s line). */
@StringRes
internal fun failureText(error: com.zephyr.engine.ZephyrError?): Int =
    // Issue #1: `geodata missing:` gets its own hint instead of the generic "core couldn't start".
    if (com.zephyr.app.vpn.ReconnectBackoff.isGeodataMissing(error)) R.string.home_failure_geodata else failureText(error?.code)

@StringRes
internal fun failureText(code: com.zephyr.engine.ErrorCode?): Int = when (code) {
    com.zephyr.engine.ErrorCode.SUBSCRIPTION_NOT_FOUND -> R.string.home_failure_no_subscription
    com.zephyr.engine.ErrorCode.VPN_PERMISSION_DENIED -> R.string.home_failure_vpn_permission
    com.zephyr.engine.ErrorCode.NETWORK_UNAVAILABLE -> R.string.home_failure_network
    else -> R.string.home_failure_core
}
