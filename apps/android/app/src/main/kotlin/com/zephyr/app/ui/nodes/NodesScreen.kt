package com.zephyr.app.ui.nodes

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
import androidx.compose.ui.semantics.collectionInfo
import androidx.compose.ui.semantics.CollectionInfo
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.zephyr.app.ui.common.PageScaffold
import com.zephyr.design.components.ZChip
import com.zephyr.design.components.ZEmptyState
import com.zephyr.design.components.ZSearchField
import com.zephyr.design.components.ZSurface
import com.zephyr.design.components.ZSurfaceStyle
import com.zephyr.design.components.ZText
import com.zephyr.design.format.ZFormat
import com.zephyr.design.theme.ZTheme
import com.zephyr.design.tokens.ZMotion
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.launch
import kotlin.math.roundToInt


/** Node library (prototype `nodes`): 13,109,802 rows, fixed row height, region rail, index search. */
@Composable
fun NodesScreen(vm: NodesViewModel, initialQuery: String, back: String = "资料库", onBack: () -> Unit, onImport: () -> Unit = {}) {
    val c = ZTheme.colors
    val ui by vm.ui.collectAsStateWithLifecycle()
    LaunchedEffect(initialQuery) { vm.setQuery(initialQuery, immediate = true) }
    val result = ui.result
    val rowCount = result?.rowCount?.coerceAtMost(Int.MAX_VALUE.toLong())?.toInt() ?: 0
    val list = rememberLazyListState()
    val scope = rememberCoroutineScope()

    // Settle → test visible rows (tokens motion.settle-delay).
    LaunchedEffect(list, result?.token) {
        snapshotFlow { list.isScrollInProgress to list.firstVisibleItemIndex }.distinctUntilChanged().collectLatest { (scrolling, _) ->
            if (scrolling) return@collectLatest
            delay(ZMotion.settleDelay.toLong())
            val ids = list.layoutInfo.visibleItemsInfo.mapNotNull { info ->
                (vm.rowAt(info.index) as? NodeRow.Node)?.let { vm.node(it.ordinal) }?.takeIf { it.latencyMs == null }?.id
            }
            vm.testVisible(ids)
        }
    }
    LaunchedEffect(result?.token) { list.scrollToItem(0) }

    PageScaffold(back = back, title = "节点", onBack = onBack) {
        Column(Modifier.fillMaxSize()) {
            Row(Modifier.padding(horizontal = 22.dp), verticalAlignment = Alignment.Bottom) {
                ZText(ZFormat.grouped(ui.total), style = ZTheme.type.hero.copy(fontSize = ZTheme.type.hero.fontSize * 0.86f))
                Spacer(Modifier.width(8.dp))
                ZText("个", Modifier.padding(bottom = 10.dp), style = ZTheme.type.body, color = c.text3)
            }
            ZText(listOfNotNull(ui.subscriptionCount.takeIf { it > 0 }?.let { "来自 $it 个订阅" }, "${ui.regionCount} 个地区").joinToString(" · "), Modifier.padding(horizontal = 22.dp), style = ZTheme.type.footnote, color = c.text3)
            Spacer(Modifier.height(18.dp))
            var composing by remember { mutableStateOf(false) }
            ZSearchField(
                ui.query, { vm.setQuery(it, composing = composing) }, "地区、城市或线路", Modifier.padding(horizontal = 16.dp),
                onComposingChange = { composing = it; if (!it) vm.setQuery(ui.query) },
            )
            if (ui.query.isNotBlank() && result != null) {
                ZText("${ZFormat.grouped(result.total)} 个 · ${ZFormat.micros(result.tookMicros)}", Modifier.padding(start = 22.dp, top = 8.dp), style = ZTheme.type.caption, color = c.text3)
            }
            Spacer(Modifier.height(12.dp))
            LazyRow(contentPadding = PaddingValues(horizontal = 16.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                item { ZChip("全部", ui.query.isBlank(), { vm.setQuery("", true) }) }
                items(ui.chips, key = { it.first }) { (code, n) -> ZChip(code, ui.query.trim().equals(code, true), { vm.setQuery(code, true) }, detail = ZFormat.wan(n)) }
            }
            Spacer(Modifier.height(10.dp))
            Box(Modifier.weight(1f).fillMaxWidth()) {
                if (result != null && rowCount == 0 && ui.query.isBlank()) {
                    ZEmptyState("还没有节点", Modifier.align(Alignment.Center), message = "导入订阅后，节点会出现在这里", action = "导入订阅", onAction = onImport)
                } else if (result != null && rowCount == 0) {
                    ZEmptyState("无结果", Modifier.align(Alignment.Center), message = "没有与“${ui.query.trim()}”匹配的节点")
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
                                    NodeRowView(n, result?.highlights.orEmpty(), vm.latency[n?.id ?: -1L], n != null && vm.testing[n.id] == true)
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
                    Footer(vm, list, ui.testedCount, result?.total ?: 0, Modifier.align(Alignment.BottomCenter))
                }
            }
        }
    }
}

@Composable
private fun PinnedHeader(vm: NodesViewModel, list: androidx.compose.foundation.lazy.LazyListState) {
    val show by remember { derivedStateOf { list.firstVisibleItemIndex > 0 || list.firstVisibleItemScrollOffset > 20 } }
    val sec by remember { derivedStateOf { vm.sectionAt(list.firstVisibleItemIndex) } }
    if (show) sec?.let { Box(Modifier.background(ZTheme.colors.bg).padding(end = 34.dp)) { SectionHeaderRow(it) } }
}

@Composable
private fun Footer(vm: NodesViewModel, list: androidx.compose.foundation.lazy.LazyListState, tested: Long, total: Long, modifier: Modifier) {
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
        ZText("已检测 ${ZFormat.grouped(tested)}", style = ZTheme.type.monoSmall, color = c.text3)
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
        codes.forEach { ZText(it, style = ZTheme.type.monoSmall.copy(fontSize = ZTheme.type.caption.fontSize * 0.92f), color = c.accent) }
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
