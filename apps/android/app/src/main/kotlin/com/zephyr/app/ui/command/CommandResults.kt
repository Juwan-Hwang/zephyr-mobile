package com.zephyr.app.ui.command

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.relocation.BringIntoViewRequester
import androidx.compose.foundation.relocation.bringIntoViewRequester
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.zephyr.app.R
import com.zephyr.design.components.ZCard
import com.zephyr.design.components.ZDivider
import com.zephyr.design.components.ZIcon
import com.zephyr.design.components.ZIcons
import com.zephyr.design.components.ZText
import com.zephyr.design.components.zPressable
import com.zephyr.design.theme.ZTheme
import com.zephyr.engine.ProxyMode

/*
 * Raycast-style command results (spec §9.5, design review J-3; mirrors iOS CommandResults.swift):
 * rows are grouped in a fixed order (commands / scenes / nodes / settings / rule test, empty groups hidden), every row
 * ends in an action label saying what Enter or a tap does (应用 / 打开 / 测试), at most 5 rows per group with a
 * 「显示全部 n 项」 footer. Enter runs the first row (Android has no ⏎ keycap: the default row's label is bold).
 * Hardware keyboard: ↓ / Tab and ↑ / Shift+Tab move a highlight over the visible rows; Enter runs the highlighted row.
 */

/** Result groups in the §9.5 order. */
enum class CommandGroup { COMMAND, SCENE, NODE, SETTINGS, RULE_TEST }

/** What the action label says. */
enum class CommandVerb { APPLY, OPEN, TEST }

/** Pages the settings group can open (the library and settings destinations). */
enum class CommandPage { NODES, SUBSCRIPTIONS, RULES, SETTINGS, TRUSTED_WIFI, LOCAL_PROXY, WIDGETS, LOGS, LICENSES }

/** What running a row does; the host turns it into a [CommandAction]. */
sealed interface CommandTarget {
    val group: CommandGroup
    val verb: CommandVerb
    data class Mode(val mode: ProxyMode) : CommandTarget { override val group get() = CommandGroup.COMMAND; override val verb get() = CommandVerb.APPLY }
    data class Toggle(val connect: Boolean) : CommandTarget { override val group get() = CommandGroup.COMMAND; override val verb get() = CommandVerb.APPLY }
    data class Scene(val id: String) : CommandTarget { override val group get() = CommandGroup.SCENE; override val verb get() = CommandVerb.OPEN }
    data class Nodes(val query: String, val nodeId: Long) : CommandTarget { override val group get() = CommandGroup.NODE; override val verb get() = CommandVerb.OPEN }
    data class Page(val page: CommandPage) : CommandTarget { override val group get() = CommandGroup.SETTINGS; override val verb get() = CommandVerb.OPEN }
    data class Rule(val input: String) : CommandTarget { override val group get() = CommandGroup.RULE_TEST; override val verb get() = CommandVerb.TEST }
}

/** One result row: [key] is stable across recompositions and unique in a result list (see [CommandResults.rows]). */
data class CommandRow(val key: String, val title: String, val subtitle: String?, val target: CommandTarget) {
    val group: CommandGroup get() = target.group
}

/** A searchable entry (mode, scene, page): matches when its label or an alias contains the typed text. */
data class CommandCandidate(
    val title: String, val subtitle: String?, val target: CommandTarget,
    val aliases: List<String> = emptyList(),
    /** Commands (mode / connect) match only from the start of a label, so a partial word never arms the wrong action. */
    val prefix: Boolean = false,
)

object CommandResults {
    const val GROUP_LIMIT = 5

    data class Grouped(val group: CommandGroup, val rows: List<CommandRow>)

    /** Case-insensitive match on the label and aliases (prefix for commands, substring otherwise); blank input matches nothing. */
    fun matches(input: String, c: CommandCandidate): Boolean {
        val q = input.trim().lowercase()
        if (q.isEmpty()) return false
        // A single letter ("d", "直") never arms a command as the Enter row; it needs two characters or the whole word.
        return (listOf(c.title) + c.aliases).any { val l = it.lowercase(); if (c.prefix) l == q || (q.length >= 2 && l.startsWith(q)) else l.contains(q) }
    }

    /** Rows with stable keys: group|title|target; a repeated row gets #n so keys stay unique. */
    fun rows(entries: List<Triple<String, String?, CommandTarget>>): List<CommandRow> {
        val seen = HashMap<String, Int>()
        return entries.map { (title, sub, target) ->
            val base = "${target.group}|$title|$target"
            val n = seen.getOrDefault(base, 0)
            seen[base] = n + 1
            CommandRow(if (n == 0) base else "$base#$n", title, sub, target)
        }
    }

    /** Fixed group order, engine/source order inside a group; empty groups are dropped. */
    fun groups(rows: List<CommandRow>): List<Grouped> =
        CommandGroup.entries.mapNotNull { g -> rows.filter { it.group == g }.takeIf { it.isNotEmpty() }?.let { Grouped(g, it) } }

    /** Rows a group shows: all when expanded or ≤ [GROUP_LIMIT], else the first [GROUP_LIMIT]. */
    fun shown(g: Grouped, expanded: Set<CommandGroup>): List<CommandRow> =
        if (g.group in expanded || g.rows.size <= GROUP_LIMIT) g.rows else g.rows.take(GROUP_LIMIT)

    /** Visible rows in screen order; keyboard movement walks this list. */
    fun visibleRows(groups: List<Grouped>, expanded: Set<CommandGroup>): List<CommandRow> = groups.flatMap { shown(it, expanded) }

    /** The row Enter runs when nothing is highlighted and there is no applicable preview: first row of the first group. */
    fun firstRow(groups: List<Grouped>): CommandRow? = groups.firstOrNull()?.rows?.firstOrNull()

    /**
     * Highlight after one step (↑ = −1, ↓ / Tab = +1); stops at both ends, never wraps (iOS moveHighlight).
     * - No highlight + an applicable preview card ([hasPrimary], Enter applies it): ↓ goes to the first row.
     * - No highlight and no preview: the first row is already the default, so ↓ goes to the second row.
     * - With a preview, ↑ from the first row returns to no highlight (Enter = apply the preview).
     */
    fun moveHighlight(current: String?, rows: List<String>, step: Int, hasPrimary: Boolean): String? {
        if (rows.isEmpty() || step == 0) return current
        val floor = if (hasPrimary) -1 else 0
        val at = current?.let { rows.indexOf(it) }?.takeIf { it >= 0 } ?: floor
        val next = (at + if (step > 0) 1 else -1).coerceIn(floor, rows.size - 1)
        return if (next < 0) null else rows[next]
    }

    /** The row Enter runs: the highlighted one, else (without a preview card) the first row; null = apply the preview. */
    fun enterRow(groups: List<Grouped>, expanded: Set<CommandGroup>, highlighted: String?, hasPrimary: Boolean): CommandRow? =
        highlighted?.let { k -> visibleRows(groups, expanded).firstOrNull { it.key == k } }
            ?: if (hasPrimary) null else firstRow(groups)
}

/**
 * The grouped list. [defaultKey] is the row Enter runs (bold label + TalkBack hint), [highlighted] the keyboard row
 * (t1 8% wash). [nodeTotal] > the node rows shown adds the node library footer instead of expanding in place.
 */
@Composable
fun CommandResultList(
    groups: List<CommandResults.Grouped>,
    expanded: Set<CommandGroup>,
    highlighted: String?,
    defaultKey: String?,
    onRun: (CommandRow) -> Unit,
    onExpand: (CommandGroup) -> Unit,
    nodeFooter: String? = null,
    onNodeFooter: () -> Unit = {},
) {
    groups.forEach { g ->
        ZText(g.group.title(), Modifier.padding(start = 14.dp, top = 24.dp, bottom = 8.dp).semantics { heading() },
            style = ZTheme.type.footnote, color = ZTheme.colors.text3)
        val shown = CommandResults.shown(g, expanded)
        ZCard {
            shown.forEachIndexed { i, row ->
                if (i > 0) ZDivider()
                ResultRow(row, isDefault = row.key == defaultKey, isHighlighted = row.key == highlighted) { onRun(row) }
            }
            val footer = when {
                shown.size < g.rows.size -> stringResource(R.string.command_show_all, g.rows.size.toString()) to { onExpand(g.group) }
                g.group == CommandGroup.NODE && nodeFooter != null -> nodeFooter to onNodeFooter
                else -> null
            }
            footer?.let { (label, onClick) ->
                ZDivider()
                ZText(label, Modifier.fillMaxWidth().zPressable(row = true, onClick = onClick).padding(horizontal = 18.dp, vertical = 14.dp),
                    style = ZTheme.type.footnote, color = ZTheme.colors.accentText)
            }
        }
    }
}

@Composable
private fun ResultRow(row: CommandRow, isDefault: Boolean, isHighlighted: Boolean, onClick: () -> Unit) {
    val c = ZTheme.colors
    val verb = row.target.verb.label()
    // TalkBack: "double tap to <verb>"; the Enter row also says "Press Enter to run" (iOS accessibilityHint).
    val hint = if (isDefault) stringResource(R.string.command_enter_hint) else null
    // Keyboard moves scroll the highlighted row into view (the IME / overlay can cover the lower groups).
    val bring = remember { BringIntoViewRequester() }
    LaunchedEffect(isHighlighted) { if (isHighlighted) runCatching { bring.bringIntoView() } }
    Row(
        Modifier.fillMaxWidth()
            .bringIntoViewRequester(bring)
            // iOS screen.pressed: a t1 wash reads on both s2 cards (surface3 is near-invisible on dark s2).
            .then(if (isHighlighted) Modifier.background(c.text1.copy(alpha = 0.08f)) else Modifier)
            .zPressable(row = true, label = verb, onClick = onClick)
            .semantics { selected = isHighlighted; if (hint != null) stateDescription = hint }
            .padding(horizontal = 18.dp, vertical = 14.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        ZIcon(row.target.icon, tint = c.text2, size = 18.dp)
        Spacer(Modifier.width(14.dp))
        Column(Modifier.weight(1f)) {
            ZText(row.title, style = ZTheme.type.body, maxLines = 1, overflow = TextOverflow.Ellipsis)
            row.subtitle?.let { ZText(it, style = ZTheme.type.caption, color = c.text3, maxLines = 1, overflow = TextOverflow.Ellipsis) }
        }
        Spacer(Modifier.width(10.dp))
        // §9.5: footnote, accent.*.text, no fill; Android marks the Enter row with a bold label instead of a ⏎ keycap.
        ZText(verb, style = if (isDefault) ZTheme.type.footnote.copy(fontWeight = FontWeight.Bold) else ZTheme.type.footnote,
            color = c.accentText, maxLines = 1)
    }
}

@Composable
private fun CommandGroup.title(): String = stringResource(when (this) {
    CommandGroup.COMMAND -> R.string.command_section_command
    CommandGroup.SCENE -> R.string.common_scenes
    CommandGroup.NODE -> R.string.common_nodes
    CommandGroup.SETTINGS -> R.string.common_settings
    CommandGroup.RULE_TEST -> R.string.command_group_rule_test
})

@Composable
private fun CommandVerb.label(): String = stringResource(when (this) {
    CommandVerb.APPLY -> R.string.common_apply
    CommandVerb.OPEN -> R.string.command_action_open
    CommandVerb.TEST -> R.string.command_action_test
})

private val CommandTarget.icon: ImageVector get() = when (this) {
    is CommandTarget.Mode -> ZIcons.Globe
    is CommandTarget.Toggle -> ZIcons.Bolt
    is CommandTarget.Scene -> ZIcons.ArrowRight
    is CommandTarget.Nodes -> ZIcons.Search
    is CommandTarget.Page -> ZIcons.Grid
    is CommandTarget.Rule -> ZIcons.Check
}
