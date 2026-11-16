package com.zephyr.app.ui.subs

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalResources
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.zephyr.app.R
import com.zephyr.app.di.AppGraph
import com.zephyr.app.ui.common.BackTo
import com.zephyr.app.ui.common.PageScaffold
import com.zephyr.app.ui.common.toPluralCount
import com.zephyr.design.components.ZCard
import com.zephyr.design.components.ZDivider
import com.zephyr.design.components.ZIconButton
import com.zephyr.design.components.ZIcons
import com.zephyr.design.components.ZListGroup
import com.zephyr.design.components.ZProgressBar
import com.zephyr.design.components.ZSectionHeader
import com.zephyr.design.components.ZSettingsRow
import com.zephyr.design.components.ZText
import com.zephyr.design.components.ZToggle
import com.zephyr.design.format.ZFormat
import com.zephyr.design.theme.ZTheme
import com.zephyr.engine.Settings
import com.zephyr.engine.SubscriptionsSummary
import kotlinx.coroutines.launch

@Composable
fun SubscriptionsScreen(back: BackTo = BackTo.LIBRARY, onBack: () -> Unit, onImport: () -> Unit) {
    val engine = AppGraph.engine
    val c = ZTheme.colors
    val subs by engine.subscriptions().collectAsState(emptyList())
    val settings by engine.settings().collectAsState(Settings())
    val summary by produceState(SubscriptionsSummary(0, 0), subs) { value = engine.subscriptionsSummary() }
    val scope = rememberCoroutineScope()
    val clock = com.zephyr.app.ui.common.LocalNow.current
    // Ticks once a minute so "2 小时前" / "26 天后到期" stay true while the page is open (review L-P2-9).
    var busyId by remember { mutableStateOf<String?>(null) }
    var pendingDelete by remember { mutableStateOf<String?>(null) }
    var error by remember { mutableStateOf<String?>(null) }
    val now by androidx.compose.runtime.produceState(clock()) { while (true) { kotlinx.coroutines.delay(60_000); value = clock() } }
    var updating by remember { mutableStateOf(false) }
    val res = LocalResources.current

    PageScaffold(back, stringResource(R.string.common_subscriptions), onBack, trailing = { ZIconButton(ZIcons.Plus, stringResource(R.string.subs_add), onImport, tint = c.accent) }) {
        Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState())) {
            Row(Modifier.padding(horizontal = 22.dp), verticalAlignment = Alignment.Bottom) {
                ZText("${summary.count}", style = ZTheme.type.hero.copy(fontSize = ZTheme.type.hero.fontSize * 0.86f))
                Spacer(Modifier.width(8.dp))
                val unit = pluralStringResource(R.plurals.subs_total_unit, summary.count)
                ZText(unit + " · " + pluralStringResource(R.plurals.subs_update_every, settings.autoUpdateHours, settings.autoUpdateHours), Modifier.padding(bottom = 10.dp), style = ZTheme.type.body, color = c.text3)
            }
            Spacer(Modifier.height(16.dp))
            subs.firstOrNull { it.lastDiff != null }?.let { s ->
                val d = s.lastDiff!!
                ZCard(Modifier.padding(horizontal = 16.dp), padding = 18.dp) {
                    Row {
                        ZText(stringResource(if (updating) R.string.subs_diff_updating else R.string.subs_diff_updated, s.name), Modifier.weight(1f), style = ZTheme.type.headline.copy(fontWeight = ZTheme.type.body.fontWeight))
                        s.updatedAt?.let { ZText(ZFormat.ago(res, it, now), style = ZTheme.type.footnote, color = c.text3) }
                    }
                    Spacer(Modifier.height(12.dp))
                    Row(horizontalArrangement = Arrangement.spacedBy(28.dp)) {
                        Delta("+" + ZFormat.grouped(d.addedNodes), stringResource(R.string.common_nodes), c.connected)
                        Delta("−" + ZFormat.grouped(d.removedNodes), stringResource(R.string.common_nodes), c.danger)
                        Delta(ZFormat.grouped(d.ruleChanges), stringResource(R.string.subs_rule_changes), c.text1)
                    }
                    Spacer(Modifier.height(14.dp)); ZDivider(inset = false); Spacer(Modifier.height(14.dp))
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Box(Modifier.size(7.dp).background(c.connected, CircleShape)); Spacer(Modifier.width(10.dp))
                        val kept = if (d.overridesKept) stringResource(R.string.subs_overrides_kept) else null
                        val retested = if (d.scenesRetested) stringResource(R.string.subs_scenes_retested) else null
                        ZText(listOfNotNull(kept, retested).joinToString(" · "), style = ZTheme.type.callout, color = c.text2)
                    }
                }
            }
            Spacer(Modifier.height(18.dp))
            ZSectionHeader(stringResource(R.string.subs_section_data), trailing = stringResource(R.string.subs_this_month))
            ZCard(Modifier.padding(horizontal = 16.dp)) {
                subs.forEachIndexed { i, s ->
                    if (i > 0) ZDivider(inset = false)
                    val soon = (s.expiresAt ?: Long.MAX_VALUE) - now < 3 * 86_400_000L
                    val armed = pendingDelete == s.id
                    SwipeActionsRow(
                        listOf(
                            SwipeAction(stringResource(if (busyId == s.id) R.string.subs_swipe_updating else R.string.subs_swipe_update), c.accent) {
                                scope.launch { busyId = s.id; runCatching { engine.updateSubscription(s.id) }.onFailure { error = res.getString(R.string.subs_error_update, s.name) }; busyId = null }
                            },
                            // Destructive: first tap arms, second tap deletes (no engine undo for deleteSubscription).
                            SwipeAction(stringResource(if (armed) R.string.subs_swipe_confirm_delete else R.string.subs_swipe_delete), c.danger) {
                                if (!armed) pendingDelete = s.id
                                else scope.launch { pendingDelete = null; runCatching { engine.deleteSubscription(s.id) }.onFailure { error = res.getString(R.string.subs_error_delete, s.name) } }
                            },
                        ),
                        resetKey = subs.size,
                    ) {
                    Row(Modifier.fillMaxWidth().padding(18.dp), verticalAlignment = Alignment.CenterVertically) {
                        Column(Modifier.weight(1f)) {
                            ZText(s.name, style = ZTheme.type.headline.copy(fontWeight = ZTheme.type.body.fontWeight))
                            ZText(pluralStringResource(R.plurals.common_node_count, s.nodeCount.toPluralCount(), ZFormat.grouped(s.nodeCount)) + (s.expiresAt?.let { " · " + ZFormat.expires(res, it, now) } ?: ""), style = ZTheme.type.footnote, color = c.text3)
                            Spacer(Modifier.height(10.dp))
                            val u = s.usedBytes; val t = s.totalBytes
                            ZProgressBar(if (u != null && t != null && t > 0) u.toFloat() / t else 0f, color = if (soon) c.warning else c.text3)
                        }
                        Spacer(Modifier.width(24.dp))
                        Column(horizontalAlignment = Alignment.End) {
                            ZText(s.remainingBytes?.let(ZFormat::bytesText) ?: "—", style = ZTheme.type.mono)
                            ZText(stringResource(R.string.subs_remaining), style = ZTheme.type.footnote, color = c.text3)
                        }
                    }
                    }
                }
                val others = summary.count - subs.size
                if (others > 0) {
                    ZDivider(inset = false)
                    val otherNodes = summary.totalNodes - subs.sumOf { it.nodeCount }
                    ZSettingsRow(pluralStringResource(R.plurals.subs_others, others, others), subtitle = pluralStringResource(R.plurals.common_node_count, otherNodes.toPluralCount(), ZFormat.grouped(otherNodes)))
                }
            }
            error?.let { e ->
                LaunchedEffect(e) { kotlinx.coroutines.delay(4_000); error = null }
                ZText(e, Modifier.padding(horizontal = 22.dp, vertical = 8.dp), style = ZTheme.type.footnote, color = c.danger)
            }
            Spacer(Modifier.height(18.dp))
            ZSectionHeader(stringResource(R.string.subs_section_update))
            ZListGroup {
                // Review L-P2-9: "value ›" opens its options (same popup as Settings) instead of cycling on each tap.
                com.zephyr.app.ui.settings.ChoiceRow(
                    stringResource(R.string.subs_auto_update), options = listOf(6, 12, 24).map { it to pluralStringResource(R.plurals.subs_every_hours, it, it) }, selected = settings.autoUpdateHours,
                    onSelect = { h -> scope.launch { engine.updateSettings(settings.copy(autoUpdateHours = h)) } },
                )
                ZDivider()
                ZSettingsRow(stringResource(R.string.subs_update_wifi_only), checked = settings.updateOnWifiOnly, onCheckedChange = { v -> scope.launch { engine.updateSettings(settings.copy(updateOnWifiOnly = v)) } })
                ZDivider()
                ZSettingsRow(stringResource(R.string.subs_show_changes), checked = settings.showChangesBeforeUpdate, onCheckedChange = { v -> scope.launch { engine.updateSettings(settings.copy(showChangesBeforeUpdate = v)) } })
                ZDivider()
                ZSettingsRow(stringResource(R.string.subs_update_all), onClick = { scope.launch { updating = true; runCatching { engine.updateAll() }; updating = false } }, value = if (updating) stringResource(R.string.common_updating) else null)
            }
            Spacer(Modifier.height(48.dp))
        }
    }
}

@Composable
private fun Delta(v: String, label: String, color: androidx.compose.ui.graphics.Color) {
    Column {
        // Review L-P2-9: prototype .diff .rw b is 300 22px, not the 30sp number style.
        ZText(v, style = ZTheme.type.number.copy(fontSize = 22.sp, fontWeight = androidx.compose.ui.text.font.FontWeight.Light, lineHeight = 26.sp), color = color)
        ZText(label, style = ZTheme.type.footnote, color = ZTheme.colors.text3)
    }
}
