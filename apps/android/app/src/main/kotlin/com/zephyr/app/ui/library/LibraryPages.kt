package com.zephyr.app.ui.library

import android.Manifest
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.os.Build
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import com.zephyr.app.R
import com.zephyr.app.di.AppGraph
import com.zephyr.app.di.addTrustedWifi
import com.zephyr.app.di.removeTrustedWifi
import com.zephyr.app.ui.common.BackTo
import com.zephyr.app.ui.common.PageScaffold
import com.zephyr.app.vpn.NetworkMonitor
import com.zephyr.design.components.ZButton
import com.zephyr.design.components.ZButtonKind
import com.zephyr.design.components.ZCard
import com.zephyr.design.components.ZDivider
import com.zephyr.design.components.ZListGroup
import com.zephyr.design.components.ZSectionHeader
import com.zephyr.design.components.ZSettingsRow
import com.zephyr.design.components.ZText
import com.zephyr.design.theme.ZTheme
import com.zephyr.engine.Settings
import kotlinx.coroutines.launch

/*
 * Library sub-pages (audit #208 U10; iOS TrustedWifiView / LocalProxyView / WidgetsGuideSheet). They only read and
 * write Settings; what the values do (disconnecting on a trusted network, the proxy listener) lives elsewhere.
 */

/** Footnote under a group, inset like the settings page's notes. */
@Composable
private fun Footer(text: String) {
    ZText(text, Modifier.padding(horizontal = 22.dp, vertical = 10.dp), style = ZTheme.type.footnote, color = ZTheme.colors.text3)
}

/** Plain single-line field inside a list group (no search glyph); the hint doubles as its accessible name. */
@Composable
private fun GroupField(
    value: String,
    onValueChange: (String) -> Unit,
    hint: String,
    keyboardType: KeyboardType = KeyboardType.Text,
    onDone: () -> Unit,
) {
    val c = ZTheme.colors
    Box(Modifier.fillMaxWidth().heightIn(min = 52.dp).padding(horizontal = 20.dp), contentAlignment = Alignment.CenterStart) {
        if (value.isEmpty()) ZText(hint, Modifier.clearAndSetSemantics {}, style = ZTheme.type.body, color = c.text3, maxLines = 1)
        BasicTextField(
            value = value,
            onValueChange = onValueChange,
            singleLine = true,
            textStyle = ZTheme.type.body.copy(color = c.text1),
            cursorBrush = SolidColor(c.accent),
            keyboardOptions = KeyboardOptions(keyboardType = keyboardType, imeAction = ImeAction.Done),
            keyboardActions = KeyboardActions(onDone = { onDone() }),
            modifier = Modifier.fillMaxWidth().semantics { contentDescription = hint },
        )
    }
}

/** 受信任的 Wi‑Fi: "disconnect on these networks" switch, the list (each with 删除), and a field to add a name. */
@Composable
fun TrustedWifiScreen(back: BackTo, onBack: () -> Unit) {
    val engine = AppGraph.engine
    val s by engine.settings().collectAsState(Settings())
    val scope = rememberCoroutineScope()
    var name by rememberSaveable { mutableStateOf("") }
    val trimmed = name.trim()
    val canAdd = trimmed.isNotEmpty() && trimmed !in s.trustedWifi
    fun add() { if (canAdd) { name = ""; scope.launch { engine.addTrustedWifi(trimmed) } } }

    PageScaffold(back, stringResource(R.string.settings_trusted_wifi), onBack) {
        Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState())) {
            ZListGroup {
                ZSettingsRow(
                    stringResource(R.string.trusted_wifi_disconnect), checked = s.disconnectOnTrusted,
                    onCheckedChange = { v -> scope.launch { engine.updateSettings(s.copy(disconnectOnTrusted = v)) } },
                )
            }
            Footer(stringResource(R.string.trusted_wifi_footer))
            LocationPermissionRow(s)
            ZSectionHeader(stringResource(R.string.trusted_wifi_networks), Modifier.padding(top = 12.dp))
            ZListGroup {
                s.trustedWifi.forEach { ssid ->
                    ZSettingsRow(ssid, trailing = {
                        ZButton(stringResource(R.string.subs_swipe_delete), { scope.launch { engine.removeTrustedWifi(ssid) } }, kind = ZButtonKind.Danger)
                    })
                    ZDivider()
                }
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Box(Modifier.weight(1f)) { GroupField(name, { name = it }, stringResource(R.string.trusted_wifi_add_hint), onDone = ::add) }
                    ZButton(stringResource(R.string.common_add), ::add, Modifier.padding(end = 12.dp), kind = ZButtonKind.Ghost, enabled = canAdd)
                }
            }
            Spacer(Modifier.height(32.dp))
        }
    }
}

/**
 * Location permission for trusted Wi‑Fi (audit E01/U1, from #225). Android 10+ only reveals the current SSID with
 * location permission; while trusted networks are in use and it is missing, this row says so and tapping it asks.
 * Without it the tunnel simply stays up on every network (never a wrong disconnect). Not shown where no network
 * monitor runs (previews / screenshot tests have no Activity result registry).
 */
@Composable
private fun LocationPermissionRow(s: Settings) {
    val monitor = AppGraph.network ?: return
    val ctx = LocalContext.current
    var granted by remember { mutableStateOf(NetworkMonitor.hasLocationPermission(ctx)) }
    val ask = rememberLauncherForActivityResult(ActivityResultContracts.RequestMultiplePermissions()) { res ->
        granted = res[Manifest.permission.ACCESS_FINE_LOCATION] == true
        if (granted) monitor.refresh()
    }
    if (granted || !s.disconnectOnTrusted || s.trustedWifi.none { it.isNotBlank() }) return
    ZListGroup(Modifier.padding(top = 4.dp)) {
        ZSettingsRow(
            stringResource(R.string.settings_trusted_wifi_location), chevron = true,
            onClick = { ask.launch(arrayOf(Manifest.permission.ACCESS_FINE_LOCATION, Manifest.permission.ACCESS_COARSE_LOCATION)) },
        )
    }
}

private val VALID_PORTS = 1024..65535

/** 本地代理端口: on/off, the port (1024–65535, applied explicitly) and 需要密码. */
@Composable
fun LocalProxyScreen(back: BackTo, onBack: () -> Unit) {
    val engine = AppGraph.engine
    val s by engine.settings().collectAsState(Settings())
    val scope = rememberCoroutineScope()
    val focus = LocalFocusManager.current
    var port by rememberSaveable { mutableStateOf("") }
    var edited by rememberSaveable { mutableStateOf(false) }
    LaunchedEffect(s.localProxyPort) { if (!edited) port = s.localProxyPort.toString() }
    val parsed = port.trim().toIntOrNull()?.takeIf { it in VALID_PORTS }
    fun save() {
        val p = parsed ?: return
        focus.clearFocus(); edited = false
        if (p != s.localProxyPort) scope.launch { engine.updateSettings(s.copy(localProxyPort = p)) }
    }

    PageScaffold(back, stringResource(R.string.settings_local_proxy), onBack) {
        Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState())) {
            ZListGroup {
                ZSettingsRow(
                    stringResource(R.string.settings_local_proxy), checked = s.localProxyEnabled,
                    onCheckedChange = { v -> scope.launch { engine.updateSettings(s.copy(localProxyEnabled = v)) } },
                )
            }
            Footer(stringResource(R.string.local_proxy_footer))
            ZSectionHeader(stringResource(R.string.local_proxy_port), Modifier.padding(top = 12.dp))
            ZListGroup {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Box(Modifier.weight(1f)) {
                        GroupField(port, { port = it.filter(Char::isDigit).take(5); edited = true }, stringResource(R.string.local_proxy_port), KeyboardType.Number, onDone = ::save)
                    }
                    ZButton(stringResource(R.string.common_apply), ::save, Modifier.padding(end = 12.dp), kind = ZButtonKind.Ghost, enabled = parsed != null && parsed != s.localProxyPort)
                }
                if (port.isNotEmpty() && parsed == null) {
                    ZDivider()
                    ZText(
                        stringResource(R.string.local_proxy_port_invalid, VALID_PORTS.first, VALID_PORTS.last),
                        Modifier.padding(horizontal = 20.dp, vertical = 12.dp), style = ZTheme.type.footnote, color = ZTheme.colors.warning,
                    )
                }
            }
            Footer(stringResource(R.string.local_proxy_port_footer))
            ZSectionHeader(stringResource(R.string.local_proxy_security), Modifier.padding(top = 12.dp))
            ZListGroup {
                ZSettingsRow(
                    stringResource(R.string.settings_password_required), checked = s.localProxyAuth,
                    onCheckedChange = { v -> scope.launch { engine.updateSettings(s.copy(localProxyAuth = v)) } },
                )
            }
            Footer(stringResource(R.string.local_proxy_auth_footer))
            Spacer(Modifier.height(32.dp))
        }
    }
}

/**
 * 小组件与快捷开关: the Android shortcuts (prototype ch. 17, spec §5): the two Glance widgets, the Quick Settings tile
 * and the ongoing notification. Where the launcher / system UI supports it, "添加" asks it to place the widget or tile.
 */
@Composable
fun WidgetsScreen(back: BackTo, onBack: () -> Unit) {
    val ctx = LocalContext.current
    val canPin = remember { runCatching { AppWidgetManager.getInstance(ctx).isRequestPinAppWidgetSupported }.getOrDefault(false) }
    PageScaffold(back, stringResource(R.string.library_widgets), onBack) {
        Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = 16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Guide(stringResource(R.string.widgets_home_title), stringResource(R.string.widgets_home_steps)) {
                Widget(stringResource(R.string.widget_label), stringResource(R.string.widget_description), canPin) {
                    pinWidget(ctx, com.zephyr.app.widget.ZephyrWidgetReceiver::class.java)
                }
                Widget(stringResource(R.string.widget_usage_label), stringResource(R.string.widget_usage_description), canPin) {
                    pinWidget(ctx, com.zephyr.app.widget.ZephyrUsageWidgetReceiver::class.java)
                }
            }
            Guide(stringResource(R.string.widgets_tile_title), stringResource(R.string.widgets_tile_steps)) {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.End) {
                        ZButton(stringResource(R.string.common_add), { requestTile(ctx) }, kind = ZButtonKind.Secondary)
                    }
                }
            }
            Guide(stringResource(R.string.notif_channel_vpn), stringResource(R.string.notif_channel_vpn_desc)) {}
            Spacer(Modifier.height(20.dp))
        }
    }
}

@Composable
private fun Guide(title: String, detail: String, extra: @Composable () -> Unit) {
    ZCard(padding = 20.dp) {
        ZText(title, style = ZTheme.type.headline)
        Spacer(Modifier.height(6.dp))
        ZText(detail, style = ZTheme.type.footnote, color = ZTheme.colors.text2)
        extra()
    }
}

@Composable
private fun Widget(name: String, detail: String, canPin: Boolean, onAdd: () -> Unit) {
    Spacer(Modifier.height(12.dp))
    ZDivider(inset = false)
    Row(Modifier.fillMaxWidth().padding(top = 12.dp), verticalAlignment = Alignment.CenterVertically) {
        Column(Modifier.weight(1f)) {
            ZText(name, style = ZTheme.type.body)
            ZText(detail, style = ZTheme.type.footnote, color = ZTheme.colors.text3)
        }
        if (canPin) {
            Spacer(Modifier.width(12.dp))
            ZButton(stringResource(R.string.common_add), onAdd, kind = ZButtonKind.Secondary)
        }
    }
}

private fun pinWidget(ctx: Context, receiver: Class<*>) {
    runCatching { AppWidgetManager.getInstance(ctx).requestPinAppWidget(ComponentName(ctx, receiver), null, null) }
}

private fun requestTile(ctx: Context) {
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return
    runCatching {
        ctx.getSystemService(android.app.StatusBarManager::class.java)?.requestAddTileService(
            ComponentName(ctx, com.zephyr.app.tile.ZephyrTileService::class.java),
            ctx.getString(R.string.app_name),
            android.graphics.drawable.Icon.createWithResource(ctx, R.drawable.ic_stat_zephyr),
            ctx.mainExecutor,
        ) {}
    }
}
