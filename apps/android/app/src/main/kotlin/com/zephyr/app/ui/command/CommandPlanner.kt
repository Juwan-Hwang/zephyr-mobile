package com.zephyr.app.ui.command

import com.zephyr.app.R
import com.zephyr.app.ui.common.UiText
import com.zephyr.app.ui.common.uiText
import com.zephyr.app.ui.common.displayText
import com.zephyr.app.ui.common.sceneNameText
import com.zephyr.engine.ExitChange
import com.zephyr.engine.NodeFilterPreview
import com.zephyr.engine.SceneNodeFilter
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
        val who: UiText,
        val scene: Scene,
        val appId: String?,
        /** Region code ("JP"); the card names it in the App's language. */
        val regionCode: String,
        val available: Int,
        val node: NodeSummary,
        /** Null when the exit already is in that region (prototype `same`: no IP line). */
        val change: ExitChange?,
        /** "Claude 将不再使用固定出口 US-Fixed-01。" */
        val releasesPin: String?,
        val previousPin: Long?,
    ) : CommandPlan

    /** "AI 场景中没有英国节点。" */
    data class NoNodes(val who: UiText, val sceneLabel: UiText, val regionCode: String) : CommandPlan

    /**
     * "视频只用 4K 节点" (contract §15.h): filter the scene's candidates. [preview] null = the filter is already on
     * ([clear] offers to turn it off). When the current node is not 4K, [preview].suggested + change are shown as the
     * exit-IP line and applied together with the filter; otherwise the current node is kept.
     */
    data class Uhd(val who: UiText, val scene: Scene, val preview: NodeFilterPreview?, val clear: Boolean) : CommandPlan {
        /** "没有支持 4K 的节点": the region has none at all, the filter cannot be set. */
        val unavailable: Boolean get() = !clear && (preview == null || preview.poolMatching == 0L)
    }

    /** "GitHub 直连": host override to DIRECT, persisted in Zephyr only. */
    data class Direct(val who: UiText, val host: String, val fromRegion: String?, val fromIp: String?) : CommandPlan
}

class CommandPlanner(private val engine: ZephyrEngine) {

    suspend fun plan(p: CommandParser.Parsed): CommandPlan? {
        val svc = p.service ?: return null
        val scenes = runCatching { engine.scenes().first() }.getOrDefault(emptyList())
        val scene = scenes.firstOrNull { it.kind == svc.kind }
        // A scene word ("视频") is input vocabulary; the card names the scene as the engine does.
        // Audit #208 U6: a built-in scene is named in the App's language, not the core's Chinese name.
        val who = if (svc.isSceneWord) scene?.displayText ?: sceneNameText(svc.name) else UiText.Raw(svc.name)
        if (p.act == CommandParser.Act.DIRECT && svc.host != null) {
            val other = scene ?: scenes.firstOrNull { it.kind == SceneKind.OTHER }
            return CommandPlan.Direct(UiText.Raw(svc.name), svc.host, other?.selected?.region?.takeIf { other.selected.id >= 0 }, other?.exitIp)
        }
        if (p.act == CommandParser.Act.UHD) {
            val s = scene ?: return null
            if (s.kind != SceneKind.VIDEO) return null
            if (s.nodeFilter == SceneNodeFilter.UHD) return CommandPlan.Uhd(who, s, null, clear = true)
            val pv = runCatching { engine.previewSceneNodeFilter(s.id, SceneNodeFilter.UHD) }.getOrNull()
            return CommandPlan.Uhd(who, s, pv, clear = false)
        }
        val rg = p.region ?: return null
        if (p.act != null || scene == null || svc.kind == SceneKind.OTHER) return null
        val pool = runCatching { engine.sceneCandidates(scene.id, rg.code) }.getOrDefault(emptyList())
            .sortedBy { it.latencyMs?.takeIf { ms -> ms >= 0 } ?: Int.MAX_VALUE }
        val best = pool.firstOrNull() ?: return CommandPlan.NoNodes(
            who,
            if (scene.kind == SceneKind.AI) uiText(R.string.command_scene_ai) else uiText(R.string.command_scene_named, scene.displayText),
            rg.code,
        )
        val pin = svc.app?.let { a -> scene.exceptions.firstOrNull { it.appId == a.id } }
        val currentRegion = pin?.node?.region ?: scene.selected.region.takeIf { scene.selected.id >= 0 }
        val change = if (currentRegion == rg.code) null
        else runCatching { engine.previewSceneChange(scene.id, best.id) }.getOrNull()
            ?.let { x -> if (pin != null) x.copy(fromRegion = pin.node.region, fromIp = null) else x }
        return CommandPlan.Exit(
            who = who,
            scene = scene,
            appId = svc.app?.id,
            regionCode = rg.code,
            available = pool.size,
            node = best,
            change = change,
            releasesPin = pin?.takeIf { it.node.id != best.id }?.node?.name,
            previousPin = pin?.node?.id,
        )
    }
}
