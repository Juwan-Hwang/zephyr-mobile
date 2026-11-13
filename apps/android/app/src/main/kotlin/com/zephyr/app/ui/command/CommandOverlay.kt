package com.zephyr.app.ui.command

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.activity.compose.BackHandler
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.unit.dp
import com.zephyr.app.di.AppGraph
import com.zephyr.design.components.ZButton
import com.zephyr.design.components.ZCard
import com.zephyr.design.components.ZIcon
import com.zephyr.design.components.ZIcons
import com.zephyr.design.components.ZSearchField
import com.zephyr.design.components.ZSurface
import com.zephyr.design.components.ZText
import com.zephyr.design.components.zPressable
import com.zephyr.design.theme.ZAnim
import com.zephyr.design.theme.ZTheme
import com.zephyr.engine.NodeQueryResult
import com.zephyr.engine.NodeSummary
import com.zephyr.engine.SceneKind
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.input.OffsetMapping
import androidx.compose.ui.text.input.TransformedText
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.text.withStyle
import com.zephyr.design.components.ZButtonKind
import kotlinx.coroutines.delay

/** What the command layer asks the host to do; every exit change arrives here already previewed. */
sealed interface CommandAction {
    data class Apply(val plan: CommandPlan) : CommandAction
    data class OpenNodes(val query: String) : CommandAction
    data class TestRule(val input: String) : CommandAction
}

/**
 * "搜索或输入指令" (prototype `cmdv`, index.html 879 / 1020–1061). Empty field: example phrases that fill the
 * field (never actions). Typed text: tokens underlined in place (service blue, region green, action amber),
 * parse chips, one preview card with the exit-IP line, then "应用". Enter applies only a previewed plan.
 */
@Composable
fun BoxScope.CommandOverlay(visible: Boolean, onDismiss: () -> Unit, onAction: (CommandAction) -> Unit) {
    val c = ZTheme.colors
    var input by remember { mutableStateOf("") }
    // Node suggestions follow committed text only: no lookups on pinyin letters mid-composition (review H-P2-12).
    var composing by remember { mutableStateOf(false) }
    var committed by remember { mutableStateOf("") }
    androidx.compose.runtime.LaunchedEffect(input, composing) { if (!composing) committed = input }
    val focus = remember { FocusRequester() }
    val parsed = remember(input) { CommandParser.parse(input) }
    val planner = remember { CommandPlanner(AppGraph.engine) }
    val plan by produceState<CommandPlan?>(null, parsed, visible) {
        value = null
        if (!visible || input.isBlank()) return@produceState
        delay(80) // debounce: one engine round-trip per pause, not per keystroke
        value = planner.plan(parsed)
    }
    val nodes by produceState<Pair<NodeQueryResult, List<NodeSummary>>?>(null, committed, visible, parsed.hasChips) {
        value = null
        val q = committed.trim()
        if (!visible || q.isEmpty() || parsed.hasChips) return@produceState
        delay(120)
        value = runCatching {
            val r = AppGraph.engine.queryNodes(q)
            r to if (r.total > 0) AppGraph.engine.nodeRows(r.token, 0, 6).rows.filter { it.id >= 0 }.take(5) else emptyList()
        }.getOrNull()
    }
    val transform = remember(parsed, c) { TokenUnderline(parsed.spans, c.accent, c.connected, c.warning) }
    val apply: (CommandPlan) -> Unit = { p -> if (p !is CommandPlan.NoNodes) onAction(CommandAction.Apply(p)) }

    AnimatedVisibility(visible, enter = fadeIn(ZAnim.standard()), exit = fadeOut(ZAnim.standard())) {
        Box(Modifier.fillMaxSize().background(c.bg.copy(alpha = 0.86f)).zPressable(label = "关闭", onClick = onDismiss))
    }
    AnimatedVisibility(visible, enter = slideInVertically(ZAnim.slow()) { -it / 6 } + fadeIn(ZAnim.standard()), exit = fadeOut(ZAnim.micro())) {
        BackHandler(visible) { onDismiss() }
        LaunchedEffect(Unit) { input = ""; delay(120); runCatching { focus.requestFocus() } }
        Column(Modifier.fillMaxSize().statusBarsPadding().imePadding().padding(horizontal = 12.dp).verticalScroll(rememberScrollState())) {
            Spacer(Modifier.height(12.dp))
            Row(verticalAlignment = Alignment.CenterVertically) {
                ZSearchField(input, { input = it }, "搜索或输入指令", Modifier.weight(1f), focusRequester = focus, onComposingChange = { composing = it },
                    onSubmit = { plan?.let(apply) }, visualTransformation = transform)
                Spacer(Modifier.width(4.dp))
                ZText("取消", Modifier.zPressable(onClick = onDismiss).padding(horizontal = 8.dp, vertical = 14.dp), style = ZTheme.type.body, color = c.accent)
            }
            if (input.isBlank()) {
                Label("建议")
                CommandParser.EXAMPLES.forEach { ex ->
                    ZText(ex, Modifier.fillMaxWidth().zPressable(onClick = { input = ex }).padding(horizontal = 14.dp, vertical = 14.dp), style = ZTheme.type.body)
                }
                return@Column
            }
            if (parsed.hasChips) {
                Label("指令")
                Chips(parsed)
            }
            plan?.let { PlanCard(it, onApply = { apply(it) }) }
            nodes?.let { (r, rows) ->
                if (rows.isNotEmpty()) {
                    Label("节点")
                    rows.forEach { n -> NodeLine(n) { onAction(CommandAction.OpenNodes(input.trim())) } }
                    ZText("在节点库中查看全部 %,d 个".format(r.total), Modifier.fillMaxWidth().zPressable(onClick = { onAction(CommandAction.OpenNodes(input.trim())) }).padding(horizontal = 14.dp, vertical = 12.dp),
                        style = ZTheme.type.footnote, color = c.accent)
                }
            }
            if (looksLikeHost(input)) {
                Label("规则")
                ZText("${input.trim()} 走哪里？", Modifier.fillMaxWidth().zPressable(onClick = { onAction(CommandAction.TestRule(input.trim())) }).padding(horizontal = 14.dp, vertical = 14.dp), style = ZTheme.type.body)
            }
            if (!parsed.hasChips && plan == null && nodes?.second.isNullOrEmpty() && !looksLikeHost(input) && nodes != null) {
                ZText("无结果", Modifier.fillMaxWidth().padding(vertical = 40.dp), style = ZTheme.type.body.copy(textAlign = androidx.compose.ui.text.style.TextAlign.Center), color = c.text3)
            }
            Spacer(Modifier.height(40.dp))
        }
    }
}

@Composable
private fun Label(t: String) =
    ZText(t, Modifier.padding(start = 14.dp, top = 24.dp, bottom = 8.dp), style = ZTheme.type.caption, color = ZTheme.colors.text3)

@Composable
private fun Chips(p: CommandParser.Parsed) {
    val chips = buildList {
        p.service?.let { add((if (it.isSceneWord) "场景" else "服务") to it.name) }
        p.region?.let { add("地区" to it.name) }
        p.act?.let { add("操作" to it.label) }
        p.service?.takeIf { !it.isSceneWord }?.let { add("范围" to scopeName(it.kind)) }
    }
    Row(Modifier.padding(horizontal = 10.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        chips.forEach { (k, v) ->
            ZSurface(shape = ZTheme.shapes.surface) {
                Column(Modifier.padding(horizontal = 12.dp, vertical = 8.dp)) {
                    ZText(k, style = ZTheme.type.caption, color = ZTheme.colors.text3)
                    ZText(v, style = ZTheme.type.body)
                }
            }
        }
    }
}

private fun scopeName(k: SceneKind) = when (k) { SceneKind.AI -> "AI"; SceneKind.VIDEO -> "视频"; else -> "其他" }

@Composable
private fun PlanCard(plan: CommandPlan, onApply: () -> Unit) {
    val c = ZTheme.colors
    Spacer(Modifier.height(14.dp))
    ZCard(padding = 18.dp) {
        when (plan) {
            is CommandPlan.NoNodes -> {
                ZText("${plan.who} 使用${plan.regionName}节点", style = ZTheme.type.headline)
                Note("${plan.sceneLabel}中没有${plan.regionName}节点。", 4)
                Spacer(Modifier.height(16.dp))
                ZButton("无可用节点", {}, Modifier.fillMaxWidth(), kind = ZButtonKind.Secondary, enabled = false)
            }
            is CommandPlan.Exit -> {
                ZText("${plan.who} 使用${plan.regionName}节点", style = ZTheme.type.headline)
                Note("${plan.available} 个可用，将使用${plan.node.name}。", 4)
                plan.change?.let { x -> IpLine("${x.fromRegion} ${x.fromIp ?: ""}".trim(), "${x.toRegion} ${x.toIp ?: ""}".trim()) }
                plan.releasesPin?.let { Note("${plan.who} 将不再使用固定出口 $it。", 12) }
                Note(
                    if (plan.scene.kind == SceneKind.AI) "${plan.regionName}节点均不可用时，${plan.who} 将暂停。"
                    else "${plan.regionName}节点均不可用时，将使用场景中的其他节点。", 12,
                )
                Spacer(Modifier.height(16.dp))
                ZButton("应用", onApply, Modifier.fillMaxWidth())
            }
            is CommandPlan.Direct -> {
                ZText("${plan.who} 直连", style = ZTheme.type.headline)
                Note("${plan.who} 的流量将不经过代理。", 4)
                IpLine(listOfNotNull(plan.fromRegion, plan.fromIp).joinToString(" ").ifEmpty { "代理" }, "本机网络")
                Note("仅在 Zephyr 中生效，订阅配置保持原样。", 12)
                Spacer(Modifier.height(16.dp))
                ZButton("应用", onApply, Modifier.fillMaxWidth())
            }
        }
    }
}

@Composable
private fun Note(t: String, top: Int) {
    Spacer(Modifier.height(top.dp))
    ZText(t, style = ZTheme.type.footnote, color = ZTheme.colors.text3)
}

/** Prototype `.pv .ipl`: amber dot, "出口 IP 将更改", then from → to in mono on s3. */
@Composable
private fun IpLine(from: String, to: String) {
    val c = ZTheme.colors
    Spacer(Modifier.height(14.dp))
    Column(Modifier.fillMaxWidth().background(c.surface3, ZTheme.shapes.surface).padding(12.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Box(Modifier.width(6.dp).height(6.dp).background(c.warning, androidx.compose.foundation.shape.CircleShape))
            Spacer(Modifier.width(8.dp))
            ZText("出口 IP 将更改", style = ZTheme.type.footnote)
        }
        Spacer(Modifier.height(4.dp))
        ZText("$from → $to", style = ZTheme.type.monoSmall, color = c.text2)
    }
}

@Composable
private fun NodeLine(n: NodeSummary, onClick: () -> Unit) {
    val c = ZTheme.colors
    Row(Modifier.fillMaxWidth().zPressable(onClick = onClick).padding(horizontal = 14.dp, vertical = 12.dp), verticalAlignment = Alignment.CenterVertically) {
        ZText(n.region, style = ZTheme.type.monoSmall, color = c.text3)
        Spacer(Modifier.width(10.dp))
        ZText(n.name, Modifier.weight(1f), style = ZTheme.type.body, maxLines = 1)
        n.latencyMs?.let { ZText("$it ms", style = ZTheme.type.numeric.copy(fontSize = ZTheme.type.footnote.fontSize), color = c.text3) }
    }
}

private val HOST = Regex("^[a-z0-9-]+(\\.[a-z0-9-]+)+$|^\\d{1,3}(\\.\\d{1,3}){3}$")
private fun looksLikeHost(s: String) = HOST.matches(s.trim().lowercase())

/** Prototype `.tk.s/.r/.a`: 2 px underline per token, drawn on the real field (no mirror text). */
private class TokenUnderline(
    private val spans: List<CommandParser.Span>,
    private val service: Color, private val region: Color, private val action: Color,
) : VisualTransformation {
    override fun filter(text: AnnotatedString): TransformedText {
        if (spans.isEmpty()) return TransformedText(text, OffsetMapping.Identity)
        val out = buildAnnotatedString {
            append(text)
            spans.forEach { sp ->
                val end = (sp.start + sp.length).coerceAtMost(text.length)
                if (sp.start < end) {
                    val col = when (sp.kind) { CommandParser.Tok.SERVICE -> service; CommandParser.Tok.REGION -> region; CommandParser.Tok.ACTION -> action }
                    addStyle(SpanStyle(textDecoration = TextDecoration.Underline, color = col), sp.start, end)
                }
            }
        }
        return TransformedText(out, OffsetMapping.Identity)
    }
}
