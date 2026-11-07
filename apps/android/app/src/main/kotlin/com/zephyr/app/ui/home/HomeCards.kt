package com.zephyr.app.ui.home

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
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
    onUseRule: () -> Unit,
    onChangeNode: () -> Unit,
    onConfirm: () -> Unit,
) {
    val c = ZTheme.colors
    ZCard(Modifier.padding(horizontal = 16.dp), padding = 18.dp) {
        ZText("全局模式", style = ZTheme.type.headline.copy(fontWeight = ZTheme.type.body.fontWeight))
        Spacer(Modifier.height(6.dp))
        ZText(if (node != null) "所有流量均经由${node.name}。场景已暂停。" else "所有流量均经由同一节点。场景已暂停。", style = ZTheme.type.callout, color = c.text3)
        Spacer(Modifier.height(14.dp))
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            ZButton("使用规则模式", onUseRule, Modifier.weight(1f))
            ZButton("更换节点", onChangeNode, Modifier.weight(1f), kind = ZButtonKind.Secondary)
        }
        androidx.compose.animation.AnimatedVisibility(proposal != null) {
            val p = proposal ?: return@AnimatedVisibility
            Column {
                Spacer(Modifier.height(14.dp))
                Column(Modifier.fillMaxWidth().background(c.surface3, ZTheme.shapes.surface).padding(12.dp)) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        androidx.compose.foundation.layout.Box(Modifier.size(6.dp).background(c.warning, androidx.compose.foundation.shape.CircleShape))
                        Spacer(Modifier.width(8.dp))
                        ZText("出口 IP 将更改", style = ZTheme.type.footnote)
                    }
                    Spacer(Modifier.height(4.dp))
                    ZText("${node?.let { "${it.region} ${it.name}" } ?: "当前"} → ${p.region} ${p.name}", style = ZTheme.type.monoSmall, color = c.text2)
                }
                Spacer(Modifier.height(8.dp))
                ZText("所有 App 的出口都将变为${p.name}。", style = ZTheme.type.footnote, color = c.text3)
                Spacer(Modifier.height(12.dp))
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    ZButton("更改为${p.name}", onConfirm, Modifier.weight(1f))
                    ZButton("取消", onChangeNode, Modifier.weight(1f), kind = ZButtonKind.Secondary)
                }
            }
        }
    }
}

/** Subscriptions summary: name, remaining, usage bar, expiry (amber within 3 days). */
@Composable
fun SubscriptionsCard(subs: List<Subscription>, now: Long, onOpen: () -> Unit) {
    val c = ZTheme.colors
    ZCard(Modifier.padding(horizontal = 16.dp)) {
        subs.take(3).forEachIndexed { i, s ->
            if (i > 0) ZDivider(inset = false)
            val soon = s.expiresAt != null && s.expiresAt!! - now < 3 * 86_400_000L
            Row(Modifier.fillMaxWidth().zPressable(onClick = onOpen).padding(18.dp), verticalAlignment = Alignment.CenterVertically) {
                Column(Modifier.weight(1f)) {
                    ZText(s.name, style = ZTheme.type.headline.copy(fontWeight = ZTheme.type.body.fontWeight), maxLines = 1)
                    Spacer(Modifier.height(12.dp))
                    val used = s.usedBytes; val total = s.totalBytes
                    ZProgressBar(if (used != null && total != null && total > 0) used.toFloat() / total else 0f, color = if (soon) c.warning else c.text3)
                }
                Spacer(Modifier.width(48.dp))
                Column(horizontalAlignment = Alignment.End) {
                    s.remainingBytes?.let { ZText(ZFormat.bytesText(it), style = ZTheme.type.numeric.copy(fontSize = ZTheme.type.headline.fontSize)) }
                    s.expiresAt?.let {
                        Spacer(Modifier.height(4.dp))
                        ZText(ZFormat.expires(it, now), style = ZTheme.type.footnote, color = if (soon) c.warning else c.text3)
                    }
                }
            }
        }
    }
}
