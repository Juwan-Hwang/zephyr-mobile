package com.zephyr.app.ui.command

import com.zephyr.app.ui.common.displayName
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
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
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringArrayResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.zephyr.app.R
import com.zephyr.app.di.AppGraph
import com.zephyr.app.ui.common.resolve
import com.zephyr.design.components.ZButton
import com.zephyr.design.components.ZCard
import com.zephyr.design.components.ZIcon
import com.zephyr.design.components.ZIcons
import com.zephyr.design.components.ZSearchField
import com.zephyr.design.components.ZSurface
import com.zephyr.design.components.ZText
import com.zephyr.design.components.zPressable
import com.zephyr.design.format.ZFormat
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
    val apply: (CommandPlan) -> Unit = { p -> if (p !is CommandPlan.NoNodes && !(p is CommandPlan.Uhd && p.unavailable)) onAction(CommandAction.Apply(p)) }

    AnimatedVisibility(visible, enter = fadeIn(ZAnim.standard()), exit = fadeOut(ZAnim.standard())) {
        // Review H-P2-11: tapping the scrim dismisses without the press-scale of zPressable (the whole screen shrank).
        Box(Modifier.fillMaxSize().background(c.bg.copy(alpha = if (android.os.Build.VERSION.SDK_INT >= 31) 0.72f else 0.86f)).clickable(
            interactionSource = remember { androidx.compose.foundation.interaction.MutableInteractionSource() }, indication = null,
            onClickLabel = stringResource(com.zephyr.design.R.string.common_close), onClick = onDismiss,
        ))
    }
    AnimatedVisibility(visible, enter = slideInVertically(ZAnim.slow()) { -it / 6 } + fadeIn(ZAnim.standard()), exit = fadeOut(ZAnim.micro())) {
        BackHandler(visible) { onDismiss() }
        LaunchedEffect(Unit) { input = ""; delay(120); runCatching { focus.requestFocus() } }
        Column(Modifier.fillMaxSize().statusBarsPadding().imePadding().padding(horizontal = 12.dp).verticalScroll(rememberScrollState())) {
            Spacer(Modifier.height(12.dp))
            Row(verticalAlignment = Alignment.CenterVertically) {
                ZSearchField(input, { input = it }, stringResource(R.string.command_placeholder), Modifier.weight(1f), focusRequester = focus, onComposingChange = { composing = it },
                    onSubmit = { plan?.let(apply) }, visualTransformation = transform, large = true)
                Spacer(Modifier.width(4.dp))
                ZText(stringResource(R.string.common_cancel), Modifier.zPressable(onClick = onDismiss).padding(horizontal = 8.dp, vertical = 14.dp), style = ZTheme.type.body, color = c.accent)
            }
            if (input.isBlank()) {
                Label(stringResource(R.string.command_section_suggestions))
                stringArrayResource(R.array.command_examples).forEach { ex ->
                    ZText(ex, Modifier.fillMaxWidth().zPressable(row = true, onClick = { input = ex }).padding(horizontal = 14.dp, vertical = 14.dp), style = ZTheme.type.body)
                }
                return@Column
            }
            if (parsed.hasChips) {
                Label(stringResource(R.string.command_section_command))
                Chips(parsed)
            }
            plan?.let { PlanCard(it, onApply = { apply(it) }) }
            nodes?.let { (r, rows) ->
                if (rows.isNotEmpty()) {
                    Label(stringResource(R.string.common_nodes))
                    rows.forEach { n -> NodeLine(n) { onAction(CommandAction.OpenNodes(input.trim())) } }
                    ZText(stringResource(R.string.command_see_all_nodes, ZFormat.grouped(r.total)), Modifier.fillMaxWidth().zPressable(row = true, onClick = { onAction(CommandAction.OpenNodes(input.trim())) }).padding(horizontal = 14.dp, vertical = 12.dp),
                        style = ZTheme.type.footnote, color = c.accent)
                }
            }
            if (looksLikeHost(input)) {
                Label(stringResource(R.string.common_rules))
                ZText(stringResource(R.string.command_test_rule, input.trim()), Modifier.fillMaxWidth().zPressable(row = true, onClick = { onAction(CommandAction.TestRule(input.trim())) }).padding(horizontal = 14.dp, vertical = 14.dp), style = ZTheme.type.body)
            }
            if (!parsed.hasChips && plan == null && nodes?.second.isNullOrEmpty() && !looksLikeHost(input) && nodes != null) {
                ZText(stringResource(R.string.common_no_results), Modifier.fillMaxWidth().padding(vertical = 40.dp), style = ZTheme.type.body.copy(textAlign = androidx.compose.ui.text.style.TextAlign.Center), color = c.text3)
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
        p.service?.let { add(stringResource(if (it.isSceneWord) R.string.command_chip_scene else R.string.command_chip_service) to if (it.isSceneWord) stringResource(it.kind.nameRes) else it.name) }
        p.region?.let { add(stringResource(R.string.command_chip_region) to regionName(it.code)) }
        p.act?.let { add(stringResource(R.string.command_chip_action) to if (it == CommandParser.Act.DIRECT) stringResource(R.string.common_direct) else it.label) }
        p.service?.takeIf { !it.isSceneWord }?.let { add(stringResource(R.string.command_chip_scope) to stringResource(it.kind.nameRes)) }
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

private val SceneKind.nameRes: Int get() = when (this) { SceneKind.AI -> R.string.common_scene_ai; SceneKind.VIDEO -> R.string.common_scene_video; else -> R.string.common_scene_other }

/** Region names for the parser's codes; any other code is shown as is. */
@Composable
private fun regionName(code: String): String = when (code) {
    "JP" -> R.string.command_region_jp; "US" -> R.string.command_region_us; "HK" -> R.string.command_region_hk
    "SG" -> R.string.command_region_sg; "TW" -> R.string.command_region_tw; "GB" -> R.string.command_region_gb
    "KR" -> R.string.command_region_kr; "DE" -> R.string.command_region_de
    else -> null
}?.let { stringResource(it) } ?: code

@Composable
private fun PlanCard(plan: CommandPlan, onApply: () -> Unit) {
    val c = ZTheme.colors
    Spacer(Modifier.height(14.dp))
    ZCard(padding = 18.dp) {
        when (plan) {
            is CommandPlan.NoNodes -> {
                val region = regionName(plan.regionCode)
                ZText(stringResource(R.string.command_plan_exit_title, plan.who.resolve(), region), style = ZTheme.type.headline)
                Note(stringResource(R.string.command_plan_no_nodes, plan.sceneLabel.resolve(), region), 4)
                Spacer(Modifier.height(16.dp))
                ZButton(stringResource(R.string.command_no_nodes_available), {}, Modifier.fillMaxWidth(), kind = ZButtonKind.Secondary, enabled = false)
            }
            is CommandPlan.Exit -> {
                val region = regionName(plan.regionCode)
                ZText(stringResource(R.string.command_plan_exit_title, plan.who.resolve(), region), style = ZTheme.type.headline)
                Note(pluralStringResource(R.plurals.command_plan_exit_available, plan.available, plan.available, plan.node.name), 4)
                plan.change?.let { x -> IpLine("${x.fromRegion} ${x.fromIp ?: ""}".trim(), "${x.toRegion} ${x.toIp ?: ""}".trim()) }
                plan.releasesPin?.let { Note(stringResource(R.string.command_plan_releases_pin, plan.who.resolve(), it), 12) }
                Note(
                    if (plan.scene.kind == SceneKind.AI) stringResource(R.string.command_plan_fallback_pause, region, plan.who.resolve())
                    else stringResource(R.string.command_plan_fallback_scene, region), 12,
                )
                Spacer(Modifier.height(16.dp))
                ZButton(stringResource(R.string.common_apply), onApply, Modifier.fillMaxWidth())
            }
            is CommandPlan.Uhd -> {
                val pv = plan.preview
                ZText(stringResource(if (plan.clear) R.string.command_uhd_title_all else R.string.command_uhd_title_only, plan.who.resolve()), style = ZTheme.type.headline)
                when {
                    plan.clear -> Note(stringResource(R.string.command_uhd_clear_note, plan.scene.displayName()), 4)
                    pv == null || pv.poolMatching == 0L -> Note(stringResource(R.string.command_uhd_none), 4)
                    pv.matching == 0 -> pv.poolMatching.toInt().let { n -> Note(pluralStringResource(R.plurals.command_uhd_untested, n, n), 4) }
                    pv.currentKept -> Note(pluralStringResource(R.plurals.command_uhd_matching_keep, pv.matching, pv.total, pv.matching), 4)
                    else -> Note(pluralStringResource(R.plurals.command_uhd_matching_switch, pv.matching, pv.total, pv.matching, pv.suggested?.name ?: stringResource(R.string.command_uhd_fastest)), 4)
                }
                pv?.takeIf { !plan.clear && !it.currentKept }?.change?.let { x -> IpLine("${x.fromRegion} ${x.fromIp ?: ""}".trim(), "${x.toRegion} ${x.toIp ?: ""}".trim()) }
                if (!plan.clear && !plan.unavailable) Note(stringResource(R.string.command_uhd_auto_note), 12)
                Spacer(Modifier.height(16.dp))
                if (plan.unavailable) ZButton(stringResource(R.string.command_no_nodes_available), {}, Modifier.fillMaxWidth(), kind = ZButtonKind.Secondary, enabled = false)
                else ZButton(stringResource(R.string.common_apply), onApply, Modifier.fillMaxWidth())
            }
            is CommandPlan.Direct -> {
                ZText(stringResource(R.string.command_direct_title, plan.who.resolve()), style = ZTheme.type.headline)
                Note(stringResource(R.string.command_direct_note, plan.who.resolve()), 4)
                IpLine(listOfNotNull(plan.fromRegion, plan.fromIp).joinToString(" ").ifEmpty { stringResource(R.string.command_direct_from_proxy) }, stringResource(R.string.common_local_network))
                Note(stringResource(R.string.command_zephyr_only), 12)
                Spacer(Modifier.height(16.dp))
                ZButton(stringResource(R.string.common_apply), onApply, Modifier.fillMaxWidth())
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
            ZText(stringResource(R.string.common_exit_ip_changes), style = ZTheme.type.footnote)
        }
        Spacer(Modifier.height(4.dp))
        ZText("$from → $to", style = ZTheme.type.monoSmall, color = c.text2)
    }
}

@Composable
private fun NodeLine(n: NodeSummary, onClick: () -> Unit) {
    val c = ZTheme.colors
    Row(Modifier.fillMaxWidth().zPressable(row = true, onClick = onClick).padding(horizontal = 14.dp, vertical = 12.dp), verticalAlignment = Alignment.CenterVertically) {
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
