package com.zephyr.app.ui.common

import android.content.res.Resources
import androidx.annotation.PluralsRes
import androidx.annotation.StringRes
import androidx.compose.runtime.Composable
import androidx.compose.runtime.Immutable
import androidx.compose.runtime.ReadOnlyComposable
import androidx.compose.ui.platform.LocalResources

/**
 * Copy decided outside composition (ViewModels, importers, pure helpers) but shown in the App's language.
 * Holds a resource id and its arguments; resolved where it is drawn, so a language change re-renders it.
 * Arguments may themselves be [UiText] (e.g. an action name inside an error) and are resolved first.
 */
@Immutable
sealed interface UiText {
    data class Res(@StringRes val id: Int, val args: List<Any> = emptyList()) : UiText
    data class Plural(@PluralsRes val id: Int, val count: Int, val args: List<Any> = listOf(count)) : UiText
    /** Text that is not copy: a host, a node name, an engine message. */
    data class Raw(val text: String) : UiText

    fun resolve(res: Resources): String = when (this) {
        is Res -> if (args.isEmpty()) res.getString(id) else res.getString(id, *resolveArgs(res, args))
        is Plural -> res.getQuantityString(id, count, *resolveArgs(res, args))
        is Raw -> text
    }

    private companion object {
        fun resolveArgs(res: Resources, args: List<Any>): Array<Any> = Array(args.size) { i -> (args[i] as? UiText)?.resolve(res) ?: args[i] }
    }
}

fun uiText(@StringRes id: Int, vararg args: Any): UiText = UiText.Res(id, args.toList())
fun uiPlural(@PluralsRes id: Int, count: Int, vararg args: Any): UiText = UiText.Plural(id, count, if (args.isEmpty()) listOf(count) else args.toList())

@Composable @ReadOnlyComposable
fun UiText.resolve(): String = resolve(LocalResources.current)

/** Plural quantity for counts kept as Long (node totals): clamped, since only the plural category matters. */
fun Long.toPluralCount(): Int = coerceIn(0L, Int.MAX_VALUE.toLong()).toInt()
