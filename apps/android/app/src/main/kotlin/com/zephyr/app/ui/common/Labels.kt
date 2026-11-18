package com.zephyr.app.ui.common

import android.content.res.Resources
import androidx.compose.runtime.Composable
import androidx.compose.runtime.ReadOnlyComposable
import androidx.compose.ui.platform.LocalResources
import androidx.annotation.StringRes
import com.zephyr.app.R
import com.zephyr.engine.ProxyMode

/** Shared copy for engine enums. Ids, not strings, so the home screen, tile, widget and notification all follow the App's language. */
@get:StringRes
val ProxyMode.labelRes: Int get() = when (this) {
    ProxyMode.RULE -> R.string.common_mode_rule
    ProxyMode.GLOBAL -> R.string.common_mode_global
    ProxyMode.DIRECT -> R.string.common_mode_direct
}

@get:StringRes
val ProxyMode.hintRes: Int get() = when (this) {
    ProxyMode.RULE -> R.string.common_mode_rule_hint
    ProxyMode.GLOBAL -> R.string.common_mode_global_hint
    ProxyMode.DIRECT -> R.string.common_mode_direct_hint
}

/** "GPT、Gemini" / "GPT, Gemini": joins names with the language's list separator. */
fun Resources.joinList(items: List<String>): String = items.reduceOrNull { a, b -> getString(R.string.common_list_separator, a, b) } ?: ""

/** "GPT 和 Claude" / "GPT and Claude". */
fun Resources.joinAnd(items: List<String>): String = items.reduceOrNull { a, b -> getString(R.string.common_pair_and, a, b) } ?: ""

@Composable @ReadOnlyComposable
fun joinList(items: List<String>): String = LocalResources.current.joinList(items)

/**
 * Built-in scene names follow the App's language (audit #208 U6, iOS `Scene.displayName` / #195): the core names
 * its built-in scenes in Chinese ("AI" / "视频" / "其他"); a custom scene keeps the name the user gave it.
 */
@StringRes
fun builtInSceneNameRes(raw: String): Int? = when (raw) {
    "AI" -> R.string.common_scene_ai
    "视频" -> R.string.common_scene_video
    "其他" -> R.string.common_scene_other
    else -> null
}

/** Display name of a scene the engine named [raw]; [kind] null when only the name is known (connections, failover). */
fun sceneNameText(raw: String, kind: com.zephyr.engine.SceneKind? = null): UiText =
    (if (kind == com.zephyr.engine.SceneKind.CUSTOM) null else builtInSceneNameRes(raw))?.let { UiText.Res(it) } ?: UiText.Raw(raw)

val com.zephyr.engine.Scene.displayText: UiText get() = sceneNameText(name, kind)

fun Resources.sceneName(s: com.zephyr.engine.Scene): String = s.displayText.resolve(this)

fun Resources.sceneName(raw: String): String = sceneNameText(raw).resolve(this)

@Composable @ReadOnlyComposable
fun com.zephyr.engine.Scene.displayName(): String = LocalResources.current.sceneName(this)
