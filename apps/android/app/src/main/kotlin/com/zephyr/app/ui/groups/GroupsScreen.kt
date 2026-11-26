package com.zephyr.app.ui.groups

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.zephyr.app.R
import com.zephyr.app.ui.common.BackTo
import com.zephyr.app.ui.common.PageScaffold
import com.zephyr.app.ui.common.UiText
import com.zephyr.design.components.ZDivider
import com.zephyr.design.components.ZEmptyState
import com.zephyr.design.components.ZIcon
import com.zephyr.design.components.ZIcons
import com.zephyr.design.components.ZLatency
import com.zephyr.design.components.ZListGroup
import com.zephyr.design.components.ZSettingsRow
import com.zephyr.design.components.ZSheet
import com.zephyr.design.components.ZSkeleton
import com.zephyr.design.components.ZSurfaceLevel
import com.zephyr.design.components.ZText
import com.zephyr.design.theme.ZTheme
import com.zephyr.engine.GroupType
import com.zephyr.engine.NodeSummary

/**
 * #208: 策略组 (contract §4). Lists the subscription's own groups with their current choice; a select group opens
 * its members to pick one (selectInGroup). url-test / fallback / load-balance / relay open read-only.
 */
@Composable
fun GroupsScreen(vm: GroupsViewModel, back: BackTo = BackTo.LIBRARY, onBack: () -> Unit, onNotice: (UiText) -> Unit = {}) {
    val connected by vm.connected.collectAsStateWithLifecycle()
    val groups by vm.groups.collectAsStateWithLifecycle()
    val open by vm.open.collectAsStateWithLifecycle()
    LaunchedEffect(vm) { vm.notices.collect { onNotice(it) } }
    Box(Modifier.fillMaxSize()) {
        PageScaffold(back, stringResource(R.string.library_groups), onBack) {
            val list = groups
            when {
                list == null -> Unit // first read still on its way
                list.isEmpty() -> ZEmptyState(stringResource(if (connected) R.string.groups_none else R.string.groups_offline), Modifier.padding(top = 48.dp))
                else -> Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).navigationBarsPadding().padding(bottom = 24.dp)) {
                    ZListGroup(Modifier.padding(horizontal = 16.dp), level = ZSurfaceLevel.S1, shape = RoundedCornerShape(18.dp)) {
                        list.forEachIndexed { i, g ->
                            if (i > 0) ZDivider()
                            ZSettingsRow(
                                g.name,
                                subtitle = stringResource(typeLabel(g.type)),
                                value = g.selected ?: "—",
                                chevron = true,
                                onClick = { vm.open(g) },
                            )
                        }
                    }
                }
            }
        }
        val sort by vm.sort.collectAsStateWithLifecycle()
        GroupSheet(open, sort, onSort = vm::setSort, onPick = vm::select, onTest = vm::test, onDismiss = vm::close)
    }
}

@Composable
private fun androidx.compose.foundation.layout.BoxScope.GroupSheet(
    m: GroupsViewModel.Members?,
    sort: com.zephyr.app.ui.common.NodeSort,
    onSort: (com.zephyr.app.ui.common.NodeSort) -> Unit,
    onPick: (NodeSummary) -> Unit,
    onTest: () -> Unit,
    onDismiss: () -> Unit,
) {
    val c = ZTheme.colors
    ZSheet(
        m != null, onDismiss, m?.group?.name ?: "",
        action = m?.let { stringResource(if (it.testing) R.string.home_scene_testing else R.string.nodes_detail_test) },
        onAction = m?.takeIf { !it.testing && !it.loading }?.let { { onTest() } },
        header = {
            if (m != null) {
                com.zephyr.app.ui.common.NodeSortControl(sort, onSort, Modifier.padding(horizontal = 16.dp))
                Spacer(Modifier.height(12.dp))
            }
        },
    ) {
        val s = m ?: return@ZSheet
        val pick = PolicyGroupList.selectable(s.group)
        if (!pick) {
            ZText(stringResource(R.string.groups_read_only), Modifier.padding(horizontal = 22.dp), style = ZTheme.type.footnote, color = c.text3)
            Spacer(Modifier.height(12.dp))
        }
        ZListGroup {
            if (s.loading) {
                repeat(3) { i ->
                    if (i > 0) ZDivider()
                    Row(Modifier.height(56.dp).padding(horizontal = 20.dp), verticalAlignment = Alignment.CenterVertically) { ZSkeleton(Modifier.width(160.dp).height(14.dp)) }
                }
            } else s.rows.forEachIndexed { i, n ->
                if (i > 0) ZDivider()
                val current = PolicyGroupList.isCurrent(n, s.group.selected)
                ZSettingsRow(
                    n.name,
                    onClick = if (pick && !current) ({ onPick(n) }) else null,
                    trailing = {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            if (n.latencyMs != null || s.testing) ZLatency(n.latencyMs, s.testing, style = ZTheme.type.mono)
                            Spacer(Modifier.width(8.dp))
                            Box(Modifier.width(20.dp), contentAlignment = Alignment.Center) {
                                if (current) ZIcon(ZIcons.Check, tint = c.accentText, size = 18.dp, contentDescription = stringResource(R.string.common_current))
                            }
                        }
                    },
                )
            }
        }
        Spacer(Modifier.height(12.dp))
    }
}

private fun typeLabel(t: GroupType): Int = when (t) {
    GroupType.SELECT -> R.string.groups_type_select
    GroupType.URL_TEST -> R.string.groups_type_url_test
    GroupType.FALLBACK -> R.string.groups_type_fallback
    GroupType.LOAD_BALANCE -> R.string.groups_type_load_balance
    GroupType.RELAY -> R.string.groups_type_relay
}
