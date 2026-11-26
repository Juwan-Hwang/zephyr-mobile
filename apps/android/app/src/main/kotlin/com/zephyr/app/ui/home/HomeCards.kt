package com.zephyr.app.ui.home

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalResources
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.zephyr.app.R
import com.zephyr.design.components.ZSurfaceLevel
import androidx.compose.foundation.shape.RoundedCornerShape
import com.zephyr.design.components.ZButton
import com.zephyr.design.components.ZButtonKind
import com.zephyr.design.components.ZCard
import com.zephyr.design.components.ZDivider
import com.zephyr.design.components.ZProgressBar
import com.zephyr.design.components.ZText
import com.zephyr.design.components.zPressable
import com.zephyr.design.format.ZFormat
import com.zephyr.design.theme.ZTheme
import com.zephyr.engine.Subscription

/** Global mode replaces the scenes card (prototype `global`, 689–692): "更换节点" opens an inline confirm. */
@Composable
fun GlobalModeCard(
    node: com.zephyr.engine.NodeSummary?,
    proposal: com.zephyr.engine.NodeSummary?,
    change: com.zephyr.engine.ExitChange?,
    onUseRule: () -> Unit,
    onChangeNode: () -> Unit,
    onConfirm: () -> Unit,
    /** #208: "更换节点" is open (proposal or not); shows 「浏览全部节点」 like iOS GlobalModeCard. */
    open: Boolean = proposal != null,
    onBrowse: () -> Unit = {},
) {
    val c = ZTheme.colors
    // Review H-P2-15: prototype `.gb` padding 16, `.h` 15, `.k` 13 / 1.5 with 5 px gap; buttons are Compact ZButtons (D-P2-4).
    ZCard(Modifier.padding(horizontal = 16.dp), padding = 16.dp, level = ZSurfaceLevel.S1, shape = RoundedCornerShape(22.dp)) {
        ZText(stringResource(R.string.home_global_title), style = ZTheme.type.headline.copy(fontWeight = ZTheme.type.body.fontWeight, fontSize = 15.sp))
        Spacer(Modifier.height(5.dp))
        ZText(if (node != null) stringResource(R.string.home_global_body, node.name) else stringResource(R.string.home_global_body_any), style = ZTheme.type.callout.copy(fontSize = 13.sp, lineHeight = 19.5.sp), color = c.text3)
        Spacer(Modifier.height(14.dp))
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            ZButton(stringResource(R.string.home_global_use_rule), onUseRule, Modifier.weight(1f))
            ZButton(stringResource(R.string.home_global_change_node), onChangeNode, Modifier.weight(1f), kind = ZButtonKind.Secondary)
        }
        androidx.compose.animation.AnimatedVisibility(open || proposal != null) {
            Column {
                val p = proposal
                if (p != null) {
                    Spacer(Modifier.height(14.dp))
                    Column(Modifier.fillMaxWidth().background(c.surface3, ZTheme.shapes.surface).padding(12.dp)) {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            androidx.compose.foundation.layout.Box(Modifier.size(6.dp).background(c.warning, androidx.compose.foundation.shape.CircleShape))
                            Spacer(Modifier.width(8.dp))
                            ZText(stringResource(R.string.common_exit_ip_changes), style = ZTheme.type.footnote)
                        }
                        Spacer(Modifier.height(4.dp))
                        val from = change?.fromIp?.let { "${change.fromRegion} $it" } ?: node?.let { "${it.region} ${it.name}" } ?: stringResource(R.string.common_current)
                        val to = change?.toIp?.let { "${change.toRegion} $it" } ?: "${p.region} ${p.name}"
                        ZText("$from → $to", style = ZTheme.type.monoSmall, color = c.text2)
                    }
                    Spacer(Modifier.height(8.dp))
                    ZText(stringResource(R.string.home_global_change_note, p.name), style = ZTheme.type.footnote, color = c.text3)
                    Spacer(Modifier.height(12.dp))
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        ZButton(stringResource(R.string.home_global_change_to, p.name), onConfirm, Modifier.weight(1f))
                        ZButton(stringResource(R.string.common_cancel), onChangeNode, Modifier.weight(1f), kind = ZButtonKind.Secondary)
                    }
                }
                // #208 (iOS GlobalModeCard 「浏览全部节点」): any library node, chosen on the nodes page's detail sheet.
                Spacer(Modifier.height(if (p != null) 4.dp else 8.dp))
                ZText(
                    stringResource(R.string.home_global_browse),
                    Modifier.heightIn(min = 48.dp).zPressable(onClick = onBrowse).padding(vertical = 14.dp),
                    style = ZTheme.type.footnote, color = c.accentText,
                )
            }
        }
    }
}

/** Subscriptions summary: name, remaining, usage bar, expiry (amber per §16.e ④: ≤ 7 calendar days or ≥ 80% used). */
@Composable
fun SubscriptionsCard(subs: List<Subscription>, now: Long, onOpen: () -> Unit) {
    val c = ZTheme.colors
    ZCard(Modifier.padding(horizontal = 16.dp), level = ZSurfaceLevel.S1, shape = RoundedCornerShape(22.dp)) {
        subs.take(3).forEachIndexed { i, s ->
            if (i > 0) ZDivider(inset = false)
            val soon = com.zephyr.app.ui.subs.SubscriptionWarning.isWarning(s, now)
            Row(Modifier.fillMaxWidth().zPressable(row = true, onClick = onOpen).padding(18.dp), verticalAlignment = Alignment.CenterVertically) {
                Column(Modifier.weight(1f)) {
                    ZText(s.name, style = ZTheme.type.body, maxLines = 1)
                    Spacer(Modifier.height(12.dp))
                    val used = s.usedBytes; val total = s.totalBytes
                    ZProgressBar(if (used != null && total != null && total > 0) used.toFloat() / total else 0f, color = if (soon) c.warning else c.text3)
                }
                Spacer(Modifier.width(48.dp))
                Column(horizontalAlignment = Alignment.End) {
                    s.remainingBytes?.let { ZText(ZFormat.bytesText(it), style = ZTheme.type.numeric) }
                    s.expiresAt?.let {
                        Spacer(Modifier.height(4.dp))
                        ZText(ZFormat.expires(LocalResources.current, it, now, weekday = true, expired = stringResource(R.string.state_expired)), style = ZTheme.type.caption, color = if (com.zephyr.app.ui.subs.SubscriptionWarning.expired(it, now)) c.dangerText else if (soon) c.warningText else c.text3)
                    }
                }
            }
        }
        if (subs.size > 3) {
            ZDivider(inset = false)
            Row(Modifier.fillMaxWidth().zPressable(row = true, onClick = onOpen).padding(horizontal = 18.dp, vertical = 14.dp)) {
                ZText(pluralStringResource(R.plurals.home_subs_more, subs.size - 3, subs.size - 3), style = ZTheme.type.footnote, color = c.text3)
            }
        }
    }
}
