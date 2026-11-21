package com.zephyr.app.ui.settings

import androidx.annotation.StringRes
import com.zephyr.app.ui.library.textRes
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
import com.zephyr.design.tokens.ZAccent
import com.zephyr.engine.Accent
import com.zephyr.engine.Appearance
import com.zephyr.engine.Settings
import com.zephyr.engine.StorageInfo
import kotlinx.coroutines.launch

/** "节点 0.6 GB · 规则 1.9 GB · 可用 3.1 GB": all three in the unit of the largest (review And-6, prototype / iOS). */
@Composable
private fun storageDetail(s: StorageInfo): String {
    val like = maxOf(s.nodesBytes, s.rulesBytes, s.freeBytes)
    return stringResource(
        R.string.settings_storage_detail,
        ZFormat.bytesTextIn(s.nodesBytes, like), ZFormat.bytesTextIn(s.rulesBytes, like), ZFormat.bytesTextIn(s.freeBytes, like),
    )
}

@Composable
fun SettingsScreen(back: BackTo, onLogs: () -> Unit = {}, onTrustedWifi: () -> Unit = {}, onLocalProxy: () -> Unit = {}, onLicenses: () -> Unit = {}, onBack: () -> Unit) {
    val engine = AppGraph.engine
    val c = ZTheme.colors
    val s by engine.settings().collectAsState(Settings())
    val storage by produceState(StorageInfo(0, 0, 0)) { value = engine.storage() }
    val scope = rememberCoroutineScope()
    val write = rememberSettingsWriter()
    fun set(f: (Settings) -> Settings) = write(f)

    PageScaffold(back, stringResource(R.string.common_settings), onBack) {
        Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState())) {
            ZSectionHeader(stringResource(R.string.settings_section_connection))
            ZListGroup {
                ZSettingsRow(stringResource(R.string.settings_on_demand), checked = s.onDemand, onCheckedChange = { v -> set { it.copy(onDemand = v) } })
                ZDivider()
                // Audit #208 U10: both rows open their editable pages (shared with the library). The trusted Wi‑Fi page
                // also carries the location-permission row (#225); here the subtitle only flags that it is missing.
                TrustedWifiRow(s, onTrustedWifi)
                ZDivider()
                ZSettingsRow(
                    stringResource(R.string.settings_local_proxy),
                    subtitle = "127.0.0.1:${s.localProxyPort}" + if (s.localProxyAuth) " · " + stringResource(R.string.settings_password_required) else "",
                    value = stringResource(if (s.localProxyEnabled) R.string.common_on else R.string.common_off), chevron = true, onClick = onLocalProxy,
                )
            }
            ZSectionHeader(stringResource(R.string.settings_section_testing), Modifier.padding(top = 12.dp))
            ZListGroup {
                ZSettingsRow(stringResource(R.string.settings_test_wifi_only), checked = s.testOnWifiOnly, onCheckedChange = { v -> set { it.copy(testOnWifiOnly = v) } })
                ZDivider()
                ChoiceRow(
                    stringResource(R.string.settings_keep_results), com.zephyr.engine.SettingsCodec.LATENCY_TTL_OPTIONS.map { it to pluralStringResource(R.plurals.settings_hours, it, it) }, s.latencyTtlHours,
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
                    ZText(storageDetail(storage), style = ZTheme.type.footnote, color = c.text3)
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
                            val name = stringResource(accentName(a))
                            val z = ZAccent.valueOf(a.name)
                            val col = z.base(c.isDark)
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
            ZSectionHeader(stringResource(R.string.settings_section_about), Modifier.padding(top = 12.dp))
            ZListGroup {
                ZSettingsRow(stringResource(R.string.settings_licenses), chevron = true, onClick = onLicenses)
                ZDivider()
                val ctx = androidx.compose.ui.platform.LocalContext.current
                ZSettingsRow(stringResource(R.string.settings_source_code), subtitle = SOURCE_URL.removePrefix("https://"), chevron = true, onClick = {
                    runCatching { ctx.startActivity(android.content.Intent(android.content.Intent.ACTION_VIEW, android.net.Uri.parse(SOURCE_URL))) }
                })
            }
            ZText(stringResource(R.string.settings_local_data_note), Modifier.padding(horizontal = 22.dp, vertical = 10.dp), style = ZTheme.type.footnote, color = c.text3)
            ZText("Zephyr ${BuildConfig.VERSION_NAME} (${BuildConfig.VERSION_CODE})", Modifier.fillMaxWidth().padding(vertical = 24.dp), style = ZTheme.type.footnote.copy(textAlign = androidx.compose.ui.text.style.TextAlign.Center), color = c.text3) // #278: readable info is t3, never t4
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
private fun accentName(a: Accent): Int = when (a) {
    Accent.BLUE -> R.string.settings_accent_blue
    Accent.GREEN -> R.string.settings_accent_green
    Accent.ORANGE -> R.string.settings_accent_orange
    Accent.PINK -> R.string.settings_accent_pink
}

/**
 * 受信任 Wi‑Fi entry (audit E01/U1, U10). Android 10+ only tells an app the current SSID with location permission;
 * while trusted networks are in use and it is missing, the subtitle says so. The list editor and the permission
 * request live on [com.zephyr.app.ui.library.TrustedWifiScreen]. Previews/tests (no network monitor) skip the check.
 */
@Composable
private fun TrustedWifiRow(s: Settings, onClick: () -> Unit) {
    // Re-checked on resume (coming back from system settings); 「始终开启的 VPN」 wins (contract §16.a⑤).
    val notice = com.zephyr.app.ui.library.rememberTrustedWifiNotice(s)
    ZSettingsRow(
        stringResource(R.string.settings_trusted_wifi),
        subtitle = stringResource(notice.textRes() ?: R.string.settings_trusted_wifi_hint),
        value = joinList(s.trustedWifi).ifEmpty { stringResource(R.string.common_none) },
        chevron = true,
        onClick = onClick,
    )
}
