package com.zephyr.app.ui.command

import com.zephyr.engine.ExitChange
import com.zephyr.engine.NodeSummary
import com.zephyr.engine.Scene
import com.zephyr.engine.SceneKind
import com.zephyr.engine.ZephyrEngine
import kotlinx.coroutines.flow.first

/**
 * Prototype `render()`/`PLAN` (index.html ~1034): turns a parsed command into one previewable change.
 * Every plan is shown as a card with its exit-IP line before anything is applied (AI exits must never
 * change without the user seeing from → to, prototype 672–675 / 1041).
 */
sealed interface CommandPlan {
    /** "Gemini 使用日本节点": pins one app (exception) or, for a scene word ("视频"), the whole scene. */
    data class Exit(
        val who: String,
        val scene: Scene,
        val appId: String?,
        val regionName: String,
        val available: Int,
        val node: NodeSummary,
        /** Null when the exit already is in that region (prototype `same`: no IP line). */
        val change: ExitChange?,
        /** "Claude 将不再使用固定出口 US-Fixed-01。" */
        val releasesPin: String?,
        val previousPin: Long?,
    ) : CommandPlan

    /** "AI 场景中没有英国节点。" */
    data class NoNodes(val who: String, val sceneLabel: String, val regionName: String) : CommandPlan

    /** "GitHub 直连": host override to DIRECT, persisted in Zephyr only. */
    data class Direct(val who: String, val host: String, val fromRegion: String?, val fromIp: String?) : CommandPlan
}

class CommandPlanner(private val engine: ZephyrEngine) {

    suspend fun plan(p: CommandParser.Parsed): CommandPlan? {
        val svc = p.service ?: return null
        val scenes = runCatching { engine.scenes().first() }.getOrDefault(emptyList())
        val scene = scenes.firstOrNull { it.kind == svc.kind }
        if (p.act == CommandParser.Act.DIRECT && svc.host != null) {
            val other = scene ?: scenes.firstOrNull { it.kind == SceneKind.OTHER }
            return CommandPlan.Direct(svc.name, svc.host, other?.selected?.region?.takeIf { other.selected.id >= 0 }, other?.exitIp)
        }
        val rg = p.region ?: return null
        if (p.act != null || scene == null || svc.kind == SceneKind.OTHER) return null
        val pool = runCatching { engine.sceneCandidates(scene.id, rg.code) }.getOrDefault(emptyList())
            .sortedBy { it.latencyMs ?: Int.MAX_VALUE }
        val best = pool.firstOrNull() ?: return CommandPlan.NoNodes(
            svc.name,
            if (scene.kind == SceneKind.AI) "AI 场景" else "${scene.name}场景",
            rg.name,
        )
        val pin = svc.app?.let { a -> scene.exceptions.firstOrNull { it.appId == a.id } }
        val currentRegion = pin?.node?.region ?: scene.selected.region.takeIf { scene.selected.id >= 0 }
        val change = if (currentRegion == rg.code) null
        else runCatching { engine.previewSceneChange(scene.id, best.id) }.getOrNull()
            ?.let { x -> if (pin != null) x.copy(fromRegion = pin.node.region, fromIp = null) else x }
        return CommandPlan.Exit(
            who = svc.name,
            scene = scene,
            appId = svc.app?.id,
            regionName = rg.name,
            available = pool.size,
            node = best,
            change = change,
            releasesPin = pin?.takeIf { it.node.id != best.id }?.node?.name,
            previousPin = pin?.node?.id,
        )
    }
}
