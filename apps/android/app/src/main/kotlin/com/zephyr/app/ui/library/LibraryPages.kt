package com.zephyr.app.ui.library

import android.Manifest
import android.appwidget.AppWidgetManager
import android.content.ClipData
import android.content.ClipDescription
import android.content.ClipboardManager
import android.content.ComponentName
import android.content.Context
import android.os.Build
import android.os.PersistableBundle
import android.widget.Toast
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
import androidx.compose.ui.semantics.onClick
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
import com.zephyr.engine.core.LocalProxyCredential
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
    // §16.c: 1–32 bytes of UTF‑8, unique, at most 50.
    val canAdd = com.zephyr.app.di.TrustedWifi.add(s, trimmed) != null
    val writeSettings = com.zephyr.app.ui.settings.rememberSettingsWriter()
    fun add() { if (canAdd) { name = ""; scope.launch { engine.addTrustedWifi(trimmed) } } }

    PageScaffold(back, stringResource(R.string.settings_trusted_wifi), onBack) {
        Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState())) {
            ZListGroup {
                ZSettingsRow(
                    stringResource(R.string.trusted_wifi_disconnect), checked = s.disconnectOnTrusted,
                    onCheckedChange = { v -> writeSettings { it.copy(disconnectOnTrusted = v) } },
                )
            }
            Footer(stringResource(R.string.trusted_wifi_footer))
            TrustedWifiNoticeRow(s)
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

/** What the trusted Wi‑Fi row has to tell the user (contract §16.a⑤), most important first. */
enum class TrustedWifiNotice { NONE, ALWAYS_ON, NEEDS_PERMISSION, LOCATION_OFF }

/**
 * Pure rule shared by 设置 and the trusted Wi‑Fi page: the system's 「始终开启的 VPN」 overrides everything (Zephyr
 * never auto-disconnects then); otherwise, while trusted networks are in use, say why the SSID can't be read.
 */
fun trustedWifiNotice(s: Settings, alwaysOn: Boolean, hasPermission: Boolean, locationOn: Boolean): TrustedWifiNotice = when {
    alwaysOn -> TrustedWifiNotice.ALWAYS_ON
    !s.disconnectOnTrusted || s.trustedWifi.none { it.isNotBlank() } -> TrustedWifiNotice.NONE
    !hasPermission -> TrustedWifiNotice.NEEDS_PERMISSION
    !locationOn -> TrustedWifiNotice.LOCATION_OFF
    else -> TrustedWifiNotice.NONE
}

fun TrustedWifiNotice.textRes(): Int? = when (this) {
    TrustedWifiNotice.NONE -> null
    TrustedWifiNotice.ALWAYS_ON -> R.string.settings_trusted_wifi_always_on
    TrustedWifiNotice.NEEDS_PERMISSION -> R.string.settings_trusted_wifi_location
    TrustedWifiNotice.LOCATION_OFF -> R.string.settings_trusted_wifi_location_off
}

/**
 * Current [TrustedWifiNotice], re-read every time the screen resumes — so coming back from the system's app or
 * location settings updates the row (and re-reads the SSID once it became readable). [NONE] where no network
 * monitor runs (previews / screenshot tests).
 */
@Composable
fun rememberTrustedWifiNotice(s: Settings): TrustedWifiNotice {
    val monitor = AppGraph.network ?: return TrustedWifiNotice.NONE
    val ctx = LocalContext.current
    var perm by remember { mutableStateOf(NetworkMonitor.hasLocationPermission(ctx)) }
    var loc by remember { mutableStateOf(NetworkMonitor.locationEnabled(ctx)) }
    var always by remember { mutableStateOf(com.zephyr.app.vpn.OnDemand.alwaysOn(ctx)) }
    androidx.lifecycle.compose.LifecycleResumeEffect(Unit) {
        val readable = perm && loc
        perm = NetworkMonitor.hasLocationPermission(ctx)
        loc = NetworkMonitor.locationEnabled(ctx)
        always = com.zephyr.app.vpn.OnDemand.alwaysOn(ctx)
        if (!readable && perm && loc) monitor.refresh()
        onPauseOrDispose { }
    }
    return trustedWifiNotice(s, always, perm, loc)
}

/**
 * Trusted Wi‑Fi notice row (audit E01/U1; permission row from #225). Android 10+ only reveals the current SSID with
 * location permission and the system location switch on; while trusted networks are in use and either is missing,
 * this row says so and tapping it asks (or, once denied, opens the app's system settings; location off opens the
 * location settings). Without it the tunnel simply stays up on every network (never a wrong disconnect).
 * Under the system's 「始终开启的 VPN」 it only states that the system manages it (contract §16.a⑤).
 */
@Composable
private fun TrustedWifiNoticeRow(s: Settings) {
    val monitor = AppGraph.network ?: return
    val ctx = LocalContext.current
    val notice = rememberTrustedWifiNotice(s)
    var denied by rememberSaveable { mutableStateOf(false) }
    val ask = rememberLauncherForActivityResult(ActivityResultContracts.RequestMultiplePermissions()) { res ->
        val granted = res[Manifest.permission.ACCESS_FINE_LOCATION] == true
        denied = !granted
        if (granted) monitor.refresh()
    }
    val text = notice.textRes() ?: return
    val open: (() -> Unit)? = when (notice) {
        TrustedWifiNotice.NEEDS_PERMISSION -> {
            {
                if (denied) {
                    // Asked before and refused: the system won't show the dialog again, so go to app settings.
                    runCatching {
                        ctx.startActivity(
                            android.content.Intent(android.provider.Settings.ACTION_APPLICATION_DETAILS_SETTINGS, android.net.Uri.fromParts("package", ctx.packageName, null))
                                .addFlags(android.content.Intent.FLAG_ACTIVITY_NEW_TASK),
                        )
                    }
                } else {
                    ask.launch(arrayOf(Manifest.permission.ACCESS_FINE_LOCATION, Manifest.permission.ACCESS_COARSE_LOCATION))
                }
            }
        }
        TrustedWifiNotice.LOCATION_OFF -> {
            { runCatching { ctx.startActivity(android.content.Intent(android.provider.Settings.ACTION_LOCATION_SOURCE_SETTINGS).addFlags(android.content.Intent.FLAG_ACTIVITY_NEW_TASK)) } }
        }
        else -> null
    }
    ZListGroup(Modifier.padding(top = 4.dp)) {
        ZSettingsRow(stringResource(text), chevron = open != null, onClick = open)
    }
}

private val VALID_PORTS = 1024..65535

/**
 * 本地代理端口 (contract §16.c / §16.g ①, audit U9): on/off, the port (1024–65535, applied explicitly), 需要密码 and,
 * while it is on, the credential: user name `zephyr`, the password (hidden until tapped), copy as HTTP / SOCKS5 URL
 * (marked sensitive on Android 13+) and 重新生成密码. Changes hot-reload a running core; a failed reload is rolled
 * back by the engine and shown as 未能应用更改 (§16.b③). The credential is never put in saved instance state.
 */
@Composable
fun LocalProxyScreen(back: BackTo, onBack: () -> Unit) {
    val engine = AppGraph.engine
    val ctx = LocalContext.current
    val s by engine.settings().collectAsState(Settings())
    val scope = rememberCoroutineScope()
    val focus = LocalFocusManager.current
    var port by rememberSaveable { mutableStateOf("") }
    var edited by rememberSaveable { mutableStateOf(false) }
    var credential by remember { mutableStateOf<String?>(null) }
    var reveal by remember { mutableStateOf(false) }
    var busy by remember { mutableStateOf(false) }
    LaunchedEffect(Unit) { credential = runCatching { engine.localProxyCredential() }.getOrNull() }
    LaunchedEffect(s.localProxyPort) { if (!edited) port = s.localProxyPort.toString() }
    val parsed = port.trim().toIntOrNull()?.takeIf { it in VALID_PORTS }
    val failed = stringResource(R.string.local_proxy_apply_failed)
    fun apply(next: Settings) = scope.launch {
        runCatching { engine.updateSettings(next) }.onFailure { toast(ctx, failed) }
    }
    fun save() {
        val p = parsed ?: return
        focus.clearFocus(); edited = false
        if (p != s.localProxyPort) apply(s.copy(localProxyPort = p))
    }

    PageScaffold(back, stringResource(R.string.settings_local_proxy), onBack) {
        Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState())) {
            ZListGroup {
                ZSettingsRow(
                    stringResource(R.string.settings_local_proxy), checked = s.localProxyEnabled,
                    onCheckedChange = { v -> apply(s.copy(localProxyEnabled = v)) },
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
                        Modifier.padding(horizontal = 20.dp, vertical = 12.dp), style = ZTheme.type.footnote, color = ZTheme.colors.warningText,
                    )
                }
            }
            Footer(stringResource(R.string.local_proxy_port_footer))
            ZSectionHeader(stringResource(R.string.local_proxy_security), Modifier.padding(top = 12.dp))
            ZListGroup {
                ZSettingsRow(
                    stringResource(R.string.settings_password_required), checked = s.localProxyAuth,
                    onCheckedChange = { v -> apply(s.copy(localProxyAuth = v)) },
                )
            }
            Footer(stringResource(R.string.local_proxy_auth_footer))
            val cred = credential
            if (s.localProxyAuth && cred != null) {
                val pw = LocalProxyCredential.password(cred)
                val shown = if (reveal) pw else MASK.repeat(8)
                ZSectionHeader(stringResource(R.string.local_proxy_credentials), Modifier.padding(top = 12.dp))
                ZListGroup {
                    ZSettingsRow(stringResource(R.string.local_proxy_user_row), trailing = { ZText(LocalProxyCredential.USER, style = ZTheme.type.mono, color = ZTheme.colors.text3, maxLines = 1) })
                    ZDivider()
                    val toggleLabel = stringResource(if (reveal) R.string.local_proxy_conceal else R.string.local_proxy_reveal)
                    val hiddenLabel = stringResource(R.string.local_proxy_concealed)
                    ZSettingsRow(
                        stringResource(R.string.local_proxy_credential_row),
                        Modifier.semantics { onClick(label = toggleLabel, action = null) },
                        onClick = { reveal = !reveal },
                        trailing = {
                            ZText(
                                shown, if (reveal) Modifier else Modifier.clearAndSetSemantics { contentDescription = hiddenLabel },
                                style = ZTheme.type.mono, color = ZTheme.colors.text3, maxLines = 1,
                            )
                        },
                    )
                    val p = s.localProxyPort
                    val copied = stringResource(R.string.local_proxy_copied)
                    for ((scheme, title) in listOf("http" to R.string.local_proxy_copy_http, "socks5" to R.string.local_proxy_copy_socks)) {
                        ZDivider()
                        ZSettingsRow(
                            stringResource(title),
                            subtitle = "\u2066" + LocalProxyCredential.url(scheme, "${LocalProxyCredential.USER}:$shown", p) + "\u2069", // LTR isolate in ar / fa / ur
                            onClick = { copySensitive(ctx, LocalProxyCredential.url(scheme, cred, p), copied) },
                        )
                    }
                }
                ZListGroup(Modifier.padding(top = 12.dp)) {
                    val regenerated = stringResource(R.string.local_proxy_regenerated)
                    ZSettingsRow(
                        stringResource(R.string.local_proxy_regenerate),
                        onClick = {
                            if (!busy) scope.launch {
                                busy = true
                                runCatching { engine.resetLocalProxyCredential() }
                                    .onSuccess { credential = it; toast(ctx, regenerated) }
                                    .onFailure { credential = runCatching { engine.localProxyCredential() }.getOrNull() ?: credential; toast(ctx, failed) }
                                busy = false
                            }
                        },
                    )
                }
                Footer(stringResource(R.string.local_proxy_regenerate_footer))
            }
            Spacer(Modifier.height(32.dp))
        }
    }
}

private const val MASK = "\u2022"

private fun toast(ctx: Context, text: String) = Toast.makeText(ctx, text, Toast.LENGTH_SHORT).show()

/**
 * Copies a proxy URL with the password in it. Android 13+ hides sensitive clips from the clipboard preview
 * (`EXTRA_IS_SENSITIVE`) and shows its own confirmation, so the app only confirms on older versions.
 */
private fun copySensitive(ctx: Context, text: String, copied: String) {
    val cm = ctx.getSystemService(Context.CLIPBOARD_SERVICE) as? ClipboardManager ?: return
    val clip = ClipData.newPlainText(LocalProxyCredential.USER, text)
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
        clip.description.extras = PersistableBundle().apply { putBoolean(ClipDescription.EXTRA_IS_SENSITIVE, true) }
    }
    runCatching { cm.setPrimaryClip(clip) }
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) toast(ctx, copied)
}

/**
 * 小组件与快捷开关: the Android shortcuts (prototype ch. 17, spec §5): the two Glance widgets, the Quick Settings tile
 * and the ongoing notification. Where the launcher / system UI supports it, "添加" asks it to place the widget or tile.
 */
@Composable
fun WidgetsScreen(
    back: BackTo,
    onBack: () -> Unit,
    // Parameters for screenshot tests (layoutlib has no launcher, so the real answers hide every 添加 button).
    canPinOverride: Boolean? = null,
    canAddTile: Boolean = Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU,
) {
    val ctx = LocalContext.current
    val canPin = canPinOverride ?: remember { canPinWidgets(ctx) }
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
                if (canAddTile) {
                    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.End) {
                        AddButton { requestTile(ctx) }
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
            AddButton(onAdd)
        }
    }
}

/**
 * The trailing 「添加」 pill, as wide as its label. ZButton's pill fills the width it is offered, and a Row measures
 * unweighted children before weighted ones, so a bare ZButton took the whole row and squeezed the weighted text
 * column to ~1 glyph per line (S25 Ultra report). IntrinsicSize.Max bounds it to the label's width.
 */
@Composable
private fun AddButton(onClick: () -> Unit) {
    ZButton(stringResource(R.string.common_add), onClick, kind = ZButtonKind.Secondary)
}

private fun canPinWidgets(ctx: Context): Boolean =
    runCatching { AppWidgetManager.getInstance(ctx).isRequestPinAppWidgetSupported }.getOrDefault(false)

private fun pinWidget(ctx: Context, receiver: Class<*>) {
    // Checked again at tap time: the default launcher can change while the page is open.
    if (!canPinWidgets(ctx)) return
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
