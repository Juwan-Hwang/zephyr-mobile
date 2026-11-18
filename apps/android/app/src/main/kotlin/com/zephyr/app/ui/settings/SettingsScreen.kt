package com.zephyr.app.ui.settings

import androidx.annotation.StringRes
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.Role
import androidx.compose.foundation.selection.selectableGroup
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.setValue
import androidx.compose.runtime.produceState
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.unit.dp
import com.zephyr.app.BuildConfig
import com.zephyr.app.R
import com.zephyr.app.di.AppGraph
import com.zephyr.app.ui.common.BackTo
import com.zephyr.app.ui.common.PageScaffold
import com.zephyr.app.ui.common.joinList
import com.zephyr.design.components.ZDivider
import com.zephyr.design.components.ZListGroup
import com.zephyr.design.components.ZSectionHeader
import com.zephyr.design.components.ZSettingsRow
import com.zephyr.design.components.ZText
import com.zephyr.design.components.ZToggle
import com.zephyr.design.components.zPressable
import com.zephyr.design.format.ZFormat
import com.zephyr.design.theme.ZTheme
import com.zephyr.design.theme.darkVariant
import com.zephyr.design.tokens.ZAccent
import com.zephyr.engine.Accent
import com.zephyr.engine.Appearance
import com.zephyr.engine.Settings
import com.zephyr.engine.StorageInfo
import kotlinx.coroutines.launch

@Composable
fun SettingsScreen(back: BackTo, onLogs: () -> Unit = {}, onBack: () -> Unit) {
    val engine = AppGraph.engine
    val c = ZTheme.colors
    val s by engine.settings().collectAsState(Settings())
    val storage by produceState(StorageInfo(0, 0, 0)) { value = engine.storage() }
    val scope = rememberCoroutineScope()
    fun set(f: (Settings) -> Settings) = scope.launch { engine.updateSettings(f(s)) }

    PageScaffold(back, stringResource(R.string.common_settings), onBack) {
        Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState())) {
            ZSectionHeader(stringResource(R.string.settings_section_connection))
            ZListGroup {
                ZSettingsRow(stringResource(R.string.settings_on_demand), checked = s.onDemand, onCheckedChange = { v -> set { it.copy(onDemand = v) } })
                ZDivider()
                TrustedWifiRow(s)
                ZDivider()
                ChoiceRow(
                    stringResource(R.string.settings_local_proxy), listOf(true to stringResource(R.string.common_on), false to stringResource(R.string.common_off)), s.localProxyEnabled,
                    onSelect = { v -> set { it.copy(localProxyEnabled = v) } },
                    subtitle = "127.0.0.1:${s.localProxyPort}" + if (s.localProxyAuth) " · " + stringResource(R.string.settings_password_required) else "",
                )
            }
            ZSectionHeader(stringResource(R.string.settings_section_testing), Modifier.padding(top = 12.dp))
            ZListGroup {
                ZSettingsRow(stringResource(R.string.settings_test_wifi_only), checked = s.testOnWifiOnly, onCheckedChange = { v -> set { it.copy(testOnWifiOnly = v) } })
                ZDivider()
                ChoiceRow(
                    stringResource(R.string.settings_keep_results), (listOf(6, 24, 72) + s.latencyTtlHours).distinct().sorted().map { it to pluralStringResource(R.plurals.settings_hours, it, it) }, s.latencyTtlHours,
                    onSelect = { h -> set { it.copy(latencyTtlHours = h) } },
                )
            }
            ZSectionHeader(stringResource(R.string.settings_section_storage), Modifier.padding(top = 12.dp))
            ZListGroup {
                Column(Modifier.padding(20.dp)) {
                    ZText(stringResource(R.string.settings_storage_title), style = ZTheme.type.body)
                    Spacer(Modifier.height(12.dp))
                    StorageBar(storage)
                    Spacer(Modifier.height(8.dp))
                    ZText(stringResource(R.string.settings_storage_detail, ZFormat.bytesText(storage.nodesBytes), ZFormat.bytesText(storage.rulesBytes), ZFormat.bytesText(storage.freeBytes)), style = ZTheme.type.footnote, color = c.text3)
                }
            }
            ZSectionHeader(stringResource(R.string.settings_appearance), Modifier.padding(top = 12.dp))
            ZListGroup {
                ChoiceRow(
                    stringResource(R.string.settings_appearance),
                    listOf(
                        Appearance.SYSTEM to stringResource(R.string.settings_appearance_system),
                        Appearance.DARK to stringResource(R.string.settings_appearance_dark),
                        Appearance.LIGHT to stringResource(R.string.settings_appearance_light),
                    ),
                    s.appearance,
                    onSelect = { a -> set { it.copy(appearance = a) } },
                )
                ZDivider()
                Row(Modifier.fillMaxWidth().padding(horizontal = 20.dp, vertical = 14.dp), verticalAlignment = Alignment.CenterVertically) {
                    ZText(stringResource(R.string.settings_accent), Modifier.weight(1f), style = ZTheme.type.body)
                    // Review L-P1-5: 28 dp dot inside a 44 dp radio target, Chinese names, selected semantics, one group.
                    Row(Modifier.selectableGroup(), horizontalArrangement = Arrangement.spacedBy(0.dp)) {
                        Accent.entries.forEach { a ->
                            val name = accentName(a)?.let { stringResource(it) } ?: a.name.lowercase()
                            val z = ZAccent.valueOf(a.name)
                            val col = if (c.isDark) z.darkVariant() else z.color
                            Box(
                                Modifier.size(44.dp)
                                    .selectable(selected = s.accent == a, role = Role.RadioButton) { set { it.copy(accent = a) } }
                                    .semantics { contentDescription = name },
                                contentAlignment = Alignment.Center,
                            ) {
                                Box(
                                    Modifier.size(28.dp).clip(CircleShape).background(col)
                                        .then(if (s.accent == a) Modifier.border(2.dp, c.text1, CircleShape) else Modifier),
                                )
                            }
                        }
                    }
                }
            }
            ZSectionHeader(stringResource(R.string.settings_section_privacy), Modifier.padding(top = 12.dp))
            ZListGroup {
                ZSettingsRow(stringResource(R.string.settings_share_diagnostics), checked = s.shareDiagnostics, onCheckedChange = { v -> set { it.copy(shareDiagnostics = v) } })
            }
            ZSectionHeader(stringResource(R.string.settings_section_diagnostics), Modifier.padding(top = 12.dp))
            ZListGroup {
                ZSettingsRow(stringResource(R.string.logs_title), chevron = true, onClick = onLogs)
            }
            ZText(stringResource(R.string.settings_local_data_note), Modifier.padding(horizontal = 22.dp, vertical = 10.dp), style = ZTheme.type.footnote, color = c.text3)
            ZText("Zephyr ${BuildConfig.VERSION_NAME} (${BuildConfig.VERSION_CODE})", Modifier.fillMaxWidth().padding(vertical = 24.dp), style = ZTheme.type.footnote.copy(textAlign = androidx.compose.ui.text.style.TextAlign.Center), color = c.text4)
        }
    }
}

@Composable
private fun StorageBar(s: StorageInfo) {
    val c = ZTheme.colors
    val total = (s.nodesBytes + s.rulesBytes + s.freeBytes).coerceAtLeast(1).toFloat()
    Row(Modifier.fillMaxWidth().height(6.dp).clip(ZTheme.shapes.pill).background(c.surface4)) {
        if (s.nodesBytes > 0) Box(Modifier.weight(s.nodesBytes / total).fillMaxHeight().background(c.accent))
        if (s.rulesBytes > 0) Box(Modifier.weight(s.rulesBytes / total).fillMaxHeight().background(c.text3))
        if (s.freeBytes > 0) Box(Modifier.weight(s.freeBytes / total).fillMaxHeight())
    }
}

@StringRes
private fun accentName(a: Accent): Int? = when (a.name) {
    "BLUE" -> R.string.settings_accent_blue; "GREEN" -> R.string.settings_accent_green; "ORANGE" -> R.string.settings_accent_orange
    "PINK" -> R.string.settings_accent_pink; "PURPLE" -> R.string.settings_accent_purple; "RED" -> R.string.settings_accent_red
    "TEAL" -> R.string.settings_accent_teal; "INDIGO" -> R.string.settings_accent_indigo; "YELLOW" -> R.string.settings_accent_yellow
    "GRAPHITE" -> R.string.settings_accent_graphite
    else -> null
}

/**
 * 受信任 Wi‑Fi (audit E01/U1). Android 10+ only tells an app the current SSID with location permission, so while
 * trusted networks are in use and it is missing, the row says so and tapping it asks. Without it the tunnel simply
 * stays up on every network (never a wrong disconnect). Not shown where no network monitor runs (previews/tests).
 */
@Composable
private fun TrustedWifiRow(s: Settings) {
    val ctx = androidx.compose.ui.platform.LocalContext.current
    val monitor = AppGraph.network
    var granted by androidx.compose.runtime.remember { androidx.compose.runtime.mutableStateOf(com.zephyr.app.vpn.NetworkMonitor.hasLocationPermission(ctx)) }
    val ask = androidx.activity.compose.rememberLauncherForActivityResult(
        androidx.activity.result.contract.ActivityResultContracts.RequestMultiplePermissions(),
    ) { res ->
        granted = res[android.Manifest.permission.ACCESS_FINE_LOCATION] == true
        if (granted) monitor?.refresh()
    }
    val needs = monitor != null && !granted && s.disconnectOnTrusted && s.trustedWifi.any { it.isNotBlank() }
    ZSettingsRow(
        stringResource(R.string.settings_trusted_wifi),
        subtitle = stringResource(if (needs) R.string.settings_trusted_wifi_location else R.string.settings_trusted_wifi_hint),
        value = joinList(s.trustedWifi).ifEmpty { stringResource(R.string.common_none) },
        onClick = if (needs) {
            { ask.launch(arrayOf(android.Manifest.permission.ACCESS_FINE_LOCATION, android.Manifest.permission.ACCESS_COARSE_LOCATION)) }
        } else null,
    )
}
