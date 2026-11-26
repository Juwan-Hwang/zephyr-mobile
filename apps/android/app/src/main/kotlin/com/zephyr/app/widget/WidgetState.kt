package com.zephyr.app.widget

import com.zephyr.engine.ConnectionStatus
import com.zephyr.engine.NodeSummary
import com.zephyr.engine.PolicyGroup
import com.zephyr.engine.ProxyMode
import com.zephyr.engine.Scene
import com.zephyr.engine.SceneKind
import com.zephyr.engine.core.LiveNames
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.update

/**
 * Pure mapping from engine state to what the status widget shows (unit-tested in WidgetStateTest). Kept apart from
 * the Glance code so the rules below do not depend on a launcher.
 */
internal object WidgetState {

    /**
     * The tunnel only exists while [com.zephyr.app.vpn.ZephyrVpnService] runs. A state that still says connected /
     * connecting with no service behind it (killed process, revoked VPN, a missed teardown) is shown as disconnected,
     * never as the last thing the engine reported.
     */
    fun effectiveStatus(engine: ConnectionStatus, serviceRunning: Boolean): ConnectionStatus = when (engine) {
        ConnectionStatus.CONNECTED, ConnectionStatus.CONNECTING -> if (serviceRunning) engine else ConnectionStatus.DISCONNECTED
        else -> engine
    }

    /** mihomo group the core writes for a scene (core-mobile scenes.rs `group_name`). */
    fun sceneGroupName(scene: Scene): String = "Zephyr·${scene.name}"

    /**
     * Follows a live group's current member down to a node: a group may point at another group ("节点选择" → "香港 01").
     * Null for a group with no current member, a cycle, or a built-in policy (DIRECT / REJECT …).
     */
    fun leaf(groups: List<PolicyGroup>, group: String): String? {
        val byName = groups.associateBy { it.name }
        var name: String = byName[group]?.selected ?: return null
        val seen = mutableSetOf(group)
        while (true) {
            if (LiveNames.isBuiltin(name)) return null
            val next = byName[name] ?: return name
            if (!seen.add(name)) return null
            name = next.selected ?: return null
        }
    }

    /**
     * Each scene with its real exit. The core's own choice (selected.id ≥ 0) wins; with none yet, the live scene group's
     * current member. A scene whose exit is unknown is left out (the widget never shows a placeholder such as 「未选择」).
     */
    fun sceneExits(scenes: List<Scene>, groups: List<PolicyGroup>): List<Scene> = scenes.mapNotNull { s ->
        when {
            s.selected.id >= 0 -> s
            else -> leaf(groups, sceneGroupName(s))?.let { name ->
                s.copy(selected = NodeSummary(id = LiveNames.idOf(name), name = name, region = LiveNames.regionOf(name).takeIf { it != "UN" } ?: "", protocol = ""))
            }
        }
    }

    /**
     * Rule mode's main exit: the 「其他」 scene (where the subscription's final MATCH usually goes), else the first
     * subscription group (not GLOBAL, not a Zephyr scene group) that resolves to a node. Null when unknown.
     */
    fun ruleExit(exits: List<Scene>, groups: List<PolicyGroup>): String? {
        exits.firstOrNull { it.kind == SceneKind.OTHER }?.let { return it.selected.name }
        return groups.asSequence()
            .filter { it.name != "GLOBAL" && !it.name.startsWith("Zephyr·") }
            .mapNotNull { leaf(groups, it.name) }
            .firstOrNull()
    }

    /** The exit shown after the mode on the detail line. */
    fun exitFor(mode: ProxyMode, globalNode: String?, exits: List<Scene>, groups: List<PolicyGroup>): String? = when (mode) {
        ProxyMode.GLOBAL -> globalNode
        ProxyMode.DIRECT -> null
        ProxyMode.RULE -> ruleExit(exits, groups)
    }
}

/**
 * Bumped by [ZephyrWidget.refreshAll]. Glance runs provideGlance once per session and a later update() only
 * recomposes, so a snapshot read before provideContent stayed whatever it was when the session started (the
 * 「已连接」 left on the card after a disconnect). The widgets reload their snapshot inside the composition on every
 * bump instead.
 */
internal object WidgetRefresh {
    private val _tick = MutableStateFlow(0L)
    val tick: StateFlow<Long> = _tick
    fun bump() = _tick.update { it + 1 }
}
