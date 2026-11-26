package com.zephyr.app.ui.nodes

import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.onClick
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.gestures.detectVerticalDragGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalResources
import androidx.compose.ui.semantics.collectionInfo
import androidx.compose.ui.semantics.CollectionInfo
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.zephyr.app.R
import com.zephyr.app.ui.common.BackTo
import com.zephyr.app.ui.common.PageScaffold
import com.zephyr.app.ui.common.toPluralCount
import com.zephyr.design.components.ZChip
import com.zephyr.design.components.ZEmptyState
import com.zephyr.design.components.ZSearchField
import com.zephyr.design.components.ZSurface
import com.zephyr.design.components.ZSurfaceStyle
import com.zephyr.design.components.ZText
import com.zephyr.design.format.ZFormat
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import com.zephyr.design.theme.ZTheme
import com.zephyr.design.tokens.ZMotion
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.launch
import kotlin.math.roundToInt


/** Node library (prototype `nodes`): 13,109,802 rows, fixed row height, region rail, index search. */
@Composable
fun NodesScreen(
    vm: NodesViewModel, initialQuery: String, back: BackTo = BackTo.LIBRARY, onBack: () -> Unit, onImport: () -> Unit = {},
    /** #208: global mode — the detail sheet offers 「用作全局节点」. */
    onUseGlobal: ((com.zephyr.engine.NodeSummary) -> Unit)? = null,
) {
    val c = ZTheme.colors
    val ui by vm.ui.collectAsStateWithLifecycle()
    val sort by vm.sort.collectAsStateWithLifecycle()
    val sortedList by vm.sorted.collectAsStateWithLifecycle()
    /** Latency / name order: a flat list without region headers (null = default order, or too many to sort). */
    val flat = sortedList?.takeIf { !it.tooMany }
    LaunchedEffect(initialQuery) { vm.setQuery(initialQuery, immediate = true) }
    val result = ui.result
    val rowCount = result?.rowCount?.coerceAtMost(Int.MAX_VALUE.toLong())?.toInt() ?: 0
    val list = rememberLazyListState()
    val scope = rememberCoroutineScope()
    LaunchedEffect(ui.scrollReset) { if (ui.scrollReset > 0) list.scrollToItem(0) }

    // Settle → test visible rows (tokens motion.settle-delay).
    LaunchedEffect(list, result?.token, flat) {
        snapshotFlow { list.isScrollInProgress to list.firstVisibleItemIndex }.distinctUntilChanged().collectLatest { (scrolling, _) ->
            if (scrolling) return@collectLatest
            delay(ZMotion.settleDelay.toLong())
            val ids = list.layoutInfo.visibleItemsInfo.mapNotNull { info ->
                val n = if (flat != null) flat.rows.getOrNull(info.index) else (vm.rowAt(info.index) as? NodeRow.Node)?.let { vm.node(it.ordinal) }
                n?.takeIf { it.latencyMs == null }?.id
            }
            vm.testVisible(ids)
        }
    }
    LaunchedEffect(result?.token, sort) { list.scrollToItem(0) }

    val res = LocalResources.current
    var selected by remember { mutableStateOf<com.zephyr.engine.NodeSummary?>(null) }
    Box(Modifier.fillMaxSize()) {
    PageScaffold(back = back, title = stringResource(R.string.common_nodes), onBack = onBack) {
        Column(Modifier.fillMaxSize()) {
            Row(Modifier.padding(horizontal = 22.dp), verticalAlignment = Alignment.Bottom) {
                ZText(ZFormat.grouped(ui.total), style = ZTheme.type.hero.copy(fontSize = ZTheme.type.hero.fontSize * 0.86f))
                Spacer(Modifier.width(8.dp))
                ZText(pluralStringResource(R.plurals.nodes_total_unit, ui.total.toPluralCount()), Modifier.padding(bottom = 10.dp), style = ZTheme.type.body, color = c.text3)
            }
            val fromSubs = ui.subscriptionCount.takeIf { it > 0 }?.let { pluralStringResource(R.plurals.nodes_from_subs, it, it) }
            val judgement = judgement(ui)
            judgement?.let { ZText(it, Modifier.padding(horizontal = 22.dp), style = ZTheme.type.footnote, color = c.text2) }
            // Spec §9.2: one "A · B" midpoint per screen, and that is the sentence above; the two facts here split by an em space.
            ZText(listOfNotNull(fromSubs, pluralStringResource(R.plurals.common_region_count, ui.regionCount, ui.regionCount)).joinToString("\u2003"), Modifier.padding(horizontal = 22.dp), style = ZTheme.type.footnote, color = c.text3)
            Spacer(Modifier.height(18.dp))
            var composing by remember { mutableStateOf(false) }
            ZSearchField(
                ui.query, { vm.setQuery(it, composing = composing) }, stringResource(R.string.nodes_search_placeholder), Modifier.padding(horizontal = 16.dp),
                onComposingChange = { composing = it; if (!it) vm.setQuery(ui.query) },
                trailing = if (ui.query.isNotBlank() && result != null) stringResource(R.string.nodes_search_stats, ZFormat.grouped(result.total), ZFormat.micros(result.tookMicros)) else null,
            )
            Spacer(Modifier.height(12.dp))
            LazyRow(contentPadding = PaddingValues(horizontal = 16.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                item { ZChip(stringResource(R.string.common_all), ui.query.isBlank(), { vm.setQuery("", true) }) }
                items(ui.chips, key = { it.first }) { (code, n) -> ZChip(code, ui.query.trim().equals(code, true), { vm.setQuery(code, true) }, detail = ZFormat.chip(res, n)) }
            }
            Spacer(Modifier.height(10.dp))
            com.zephyr.app.ui.common.NodeSortControl(sort, vm::setSort, Modifier.padding(horizontal = 16.dp))
            if (sortedList?.tooMany == true) {
                Spacer(Modifier.height(6.dp))
                ZText(stringResource(R.string.nodes_sort_too_many), Modifier.padding(horizontal = 22.dp), style = ZTheme.type.footnote, color = c.text3)
            }
            Spacer(Modifier.height(10.dp))
            Box(Modifier.weight(1f).fillMaxWidth()) {
                if (ui.failed) {
                    // Audit U12: a failed query / page shows an error with "重试" instead of an empty or frozen list.
                    ZEmptyState(stringResource(R.string.nodes_error_title), Modifier.align(Alignment.Center), action = stringResource(R.string.common_try_again), onAction = { vm.retry() })
                } else if (result != null && rowCount == 0 && ui.query.isBlank()) {
                    ZEmptyState(stringResource(R.string.nodes_empty_title), Modifier.align(Alignment.Center), message = stringResource(R.string.nodes_empty_message), action = stringResource(R.string.nodes_empty_action), onAction = onImport)
                } else if (result != null && rowCount == 0) {
                    ZEmptyState(stringResource(R.string.common_no_results), Modifier.align(Alignment.Center), message = stringResource(R.string.nodes_no_match, ui.query.trim()))
                } else if (flat != null) {
                    if (flat.loading && flat.rows.isEmpty()) {
                        Column { repeat(6) { NodeRowView(null, emptyList(), null, false) } }
                    } else LazyColumn(
                        state = list,
                        modifier = Modifier.fillMaxSize().semantics { collectionInfo = CollectionInfo(flat.rows.size, 1) },
                        contentPadding = PaddingValues(bottom = 40.dp),
                    ) {
                        items(flat.rows, key = { it.id }) { n ->
                            NodeRowView(n, result?.highlights.orEmpty(), vm.latency[n.id], vm.testing[n.id] == true, onClick = { selected = n })
                        }
                    }
                } else {
                    val epoch by vm.pageEpoch
                    LaunchedEffect(list, result) {
                        snapshotFlow { list.layoutInfo.visibleItemsInfo.let { v -> if (v.isEmpty()) IntRange.EMPTY else v.first().index..v.last().index } }
                            .collect { vm.prefetch(it) }
                    }
                    LazyColumn(
                        state = list,
                        modifier = Modifier.fillMaxSize().semantics { collectionInfo = CollectionInfo(rowCount, 1) },
                        contentPadding = PaddingValues(bottom = 40.dp, end = 34.dp),
                    ) {
                        items(rowCount, key = null, contentType = { i -> if (vm.rowAt(i) is NodeRow.Header) 0 else 1 }) { i ->
                            @Suppress("UNUSED_EXPRESSION") epoch
                            when (val r = vm.rowAt(i)) {
                                is NodeRow.Header -> SectionHeaderRow(r.section)
                                is NodeRow.Node -> {
                                    val n = vm.node(r.ordinal)
                                    NodeRowView(n, result?.highlights.orEmpty(), vm.latency[n?.id ?: -1L], n != null && vm.testing[n.id] == true, onClick = { selected = n })
                                }
                                null -> Unit
                            }
                        }
                    }
                    PinnedHeader(vm, list)
                    if ((result?.sections?.size ?: 0) > 1) RegionRail(result!!.sections.map { it.region }) { f ->
                        val secs = result.sections
                        val gi = (f * secs.size).toInt().coerceIn(0, secs.size - 1)
                        val within = f * secs.size - gi
                        val target = secs[gi].rowOffset + (within * secs[gi].count).toLong()
                        scope.launch { list.scrollToItem(target.coerceAtMost(rowCount - 1L).toInt()) }
                        secs[gi]
                    }
                    Footer(vm, list, ui.testedCount.takeIf { judgement == null }, result?.total ?: 0, Modifier.align(Alignment.BottomCenter))
                }
            }
        }
    }
    val sel = selected
    NodeDetailSheet(
        sel, sel?.let { vm.latency[it.id] }, sel != null && vm.testing[sel.id] == true,
        load = { vm.detail(it) }, onTest = { vm.testOne(it.id) }, onDismiss = { selected = null },
        onUseGlobal = onUseGlobal?.let { use -> { n -> selected = null; use(n) } },
    )
    }
}

@Composable
private fun PinnedHeader(vm: NodesViewModel, list: androidx.compose.foundation.lazy.LazyListState) {
    val show by remember { derivedStateOf { list.firstVisibleItemIndex > 0 || list.firstVisibleItemScrollOffset > 20 } }
    val sec by remember { derivedStateOf { vm.sectionAt(list.firstVisibleItemIndex) } }
    if (show) sec?.let { Box(Modifier.background(ZTheme.colors.bg.copy(alpha = 0.86f)).padding(end = 34.dp)) { SectionHeaderRow(it) } }
}

@Composable
private fun Footer(vm: NodesViewModel, list: androidx.compose.foundation.lazy.LazyListState, tested: Long?, total: Long, modifier: Modifier) {
    val c = ZTheme.colors
    val pos by remember {
        derivedStateOf {
            val first = list.layoutInfo.visibleItemsInfo.firstNotNullOfOrNull { vm.rowAt(it.index) as? NodeRow.Node }
            (first?.ordinal ?: -1L) + 1
        }
    }
    Row(
        modifier.fillMaxWidth().background(c.bg.copy(alpha = 0.94f)).navigationBarsPadding().padding(horizontal = 22.dp, vertical = 8.dp),
    ) {
        ZText(if (pos > 0) "${ZFormat.grouped(pos)} / ${ZFormat.grouped(total)}" else "", style = ZTheme.type.monoSmall, color = c.text3)
        Spacer(Modifier.weight(1f))
        // §18.a: the header sentence already says "已检测 N"; the footer repeats it only when the sentence is hidden (search).
        if (tested != null) ZText(stringResource(R.string.nodes_tested, ZFormat.grouped(tested)), style = ZTheme.type.monoSmall, color = c.text3)
    }
}

/**
 * Contract §18.a / spec §9.4 header sentence under the big number, or null when it must not show: index not loaded
 * (load failure is the page's error state, never "尚未检测"), empty library, a search, or a failed query.
 * 「可连通 x · 已检测 N」 takes both numbers from one nodeFunnel; line t2, reachable number t1 (red-text when 0).
 */
@Composable
private fun judgement(ui: NodesUi): AnnotatedString? {
    if (!ui.indexLoaded || ui.total <= 0 || ui.query.isNotBlank() || ui.failed) return null
    val c = ZTheme.colors
    val r = ui.reachable
    val t = ui.funnelTested
    return when {
        r != null && t != null && t > 0 -> {
            val num = ZFormat.grouped(r)
            val text = stringResource(R.string.nodes_judgement, num, ZFormat.grouped(t))
            val at = text.indexOf(num)
            buildAnnotatedString {
                append(text)
                if (at >= 0) addStyle(SpanStyle(color = if (r == 0L) c.dangerText else c.text1), at, at + num.length)
            }
        }
        r == null && ui.testedCount > 0 -> AnnotatedString(stringResource(R.string.nodes_tested, ZFormat.grouped(ui.testedCount)))
        else -> AnnotatedString(stringResource(R.string.nodes_untested_hint))
    }
}

/** Right-edge region index: tap or drag to jump; bubble shows "JP 日本 · 12,034 / 2,204,117". */
@Composable
private fun androidx.compose.foundation.layout.BoxScope.RegionRail(codes: List<String>, onScrub: (Float) -> com.zephyr.engine.RegionSection) {
    val c = ZTheme.colors
    var bubble by remember { mutableStateOf<Pair<com.zephyr.engine.RegionSection, Float>?>(null) }
    var railH by remember { mutableFloatStateOf(1f) }
    val density = LocalDensity.current
    Column(
        Modifier.align(Alignment.CenterEnd).fillMaxHeight().width(28.dp).padding(vertical = 8.dp)
            .androidx_onSize { railH = it }
            .pointerInput(codes) {
                detectVerticalDragGestures(
                    onDragEnd = { bubble = null }, onDragCancel = { bubble = null },
                    onDragStart = { o -> val f = (o.y / railH).coerceIn(0f, 0.999f); bubble = onScrub(f) to o.y },
                ) { ch, _ -> val f = (ch.position.y / railH).coerceIn(0f, 0.999f); bubble = onScrub(f) to ch.position.y }
            }
            .pointerInput(codes) { detectTapGestures { o -> onScrub((o.y / railH).coerceIn(0f, 0.999f)) } },
        verticalArrangement = Arrangement.SpaceEvenly,
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        // Review L-P2-7: the rail is a drag target only; give TalkBack one tap-to-jump action per region instead.
        val res = LocalResources.current
        codes.forEachIndexed { i, code -> ZText(code, Modifier.semantics { contentDescription = res.getString(R.string.nodes_jump_to, code); role = androidx.compose.ui.semantics.Role.Button; onClick { onScrub((i + 0.5f) / codes.size); true } }, style = ZTheme.type.monoSmall.copy(fontSize = ZTheme.type.caption.fontSize * 0.92f), color = c.accentText) }
    }
    bubble?.let { (sec, y) ->
        ZSurface(
            Modifier.align(Alignment.TopEnd).padding(end = 40.dp).offset { IntOffset(0, (y - with(density) { 24.dp.toPx() }).roundToInt()) },
            style = ZSurfaceStyle.Glass, shape = ZTheme.shapes.surface,
        ) {
            Column(Modifier.padding(horizontal = 16.dp, vertical = 10.dp)) {
                ZText("${sec.region} ${sec.name}", style = ZTheme.type.headline)
                ZText(ZFormat.grouped(sec.count), style = ZTheme.type.monoSmall, color = c.text3)
            }
        }
    }
}

private fun Modifier.androidx_onSize(block: (Float) -> Unit) = this.then(
    Modifier.onSizeChangedCompat { block(it.toFloat()) },
)
