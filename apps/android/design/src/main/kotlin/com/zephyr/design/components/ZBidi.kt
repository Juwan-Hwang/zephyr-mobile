package com.zephyr.design.components

import androidx.compose.runtime.Composable
import androidx.compose.runtime.ReadOnlyComposable
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextDirection
import androidx.compose.ui.unit.LayoutDirection

/**
 * Bidi for text in a right-to-left layout (ar, fa, ur): every paragraph gets an explicit direction instead of
 * the content heuristic, which the first RTL snapshots showed resolving the wrong way round ("86.4 GB" drawn as
 * "GB 86.4", "182 KB/s" as "KB/s 182", "127.0.0.1:7890 · گذرواژه…" laid out left-to-right).
 *  - Copy with any Arabic-script letter is an RTL paragraph, even when it starts with a Latin name
 *    ("Gemini عبر اليابان", "Wi‑Fi مورد اعتماد"), so it reads from the right edge in logical order.
 *  - Text with no RTL letter (node names, sizes, rates, latency, times, IPs — what Zephyr keeps Latin) is an LTR
 *    run, anchored to the layout's start (right) edge so it still sits where the RTL design puts it.
 * LTR layouts are untouched, so en/zh render exactly as before.
 */
@Composable
@ReadOnlyComposable
internal fun bidiStyle(text: CharSequence, style: TextStyle): TextStyle {
    if (LocalLayoutDirection.current != LayoutDirection.Rtl || style.textDirection != TextDirection.Unspecified) return style
    if (text.any(::isRtlLetter)) return style.copy(textDirection = TextDirection.Rtl)
    val align = when (style.textAlign) {
        TextAlign.Unspecified, TextAlign.Start -> TextAlign.Right
        TextAlign.End -> TextAlign.Left
        else -> style.textAlign
    }
    return style.copy(textDirection = TextDirection.Ltr, textAlign = align)
}

private fun isRtlLetter(c: Char): Boolean = when (Character.getDirectionality(c)) {
    Character.DIRECTIONALITY_RIGHT_TO_LEFT, Character.DIRECTIONALITY_RIGHT_TO_LEFT_ARABIC -> true
    else -> false
}

/**
 * Arabic-Indic (U+0660–0669) and Extended Arabic-Indic (U+06F0–06F9) digits → Western 0–9, so a count a string
 * resource formats in the locale's numbering system never sits beside the Western sizes, rates and IPs on the
 * same screen (product choice for ar/fa/ur; see ZTheme latinDigitResources). Same length, so spans stay valid.
 */
internal fun latinDigits(text: String): String {
    if (text.none { it in '\u0660'..'\u0669' || it in '\u06F0'..'\u06F9' }) return text
    return buildString(text.length) {
        for (c in text) append(
            when (c) {
                in '\u0660'..'\u0669' -> '0' + (c - '\u0660')
                in '\u06F0'..'\u06F9' -> '0' + (c - '\u06F0')
                else -> c
            },
        )
    }
}

internal fun latinDigits(text: androidx.compose.ui.text.AnnotatedString): androidx.compose.ui.text.AnnotatedString {
    val t = latinDigits(text.text)
    return if (t === text.text) text else androidx.compose.ui.text.AnnotatedString(t, text.spanStyles, text.paragraphStyles)
}
