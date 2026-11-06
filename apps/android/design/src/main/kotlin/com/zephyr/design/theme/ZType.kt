package com.zephyr.design.theme

import androidx.compose.runtime.Immutable
import androidx.compose.ui.text.ExperimentalTextApi
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.Font
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontVariation
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.em
import androidx.compose.ui.unit.sp
import com.zephyr.design.R

/*
 * Type: Inter (variable, Latin + digits subset) with system CJK fallback; JetBrains Mono for addresses/rules.
 * Big data uses ExtraLight/Light with tabular figures; titles SemiBold (design spec §1).
 * Mobile scale: smallest interactive text 13sp (desktop's 10px caps buttons are too small on phones).
 */

@OptIn(ExperimentalTextApi::class)
private fun inter(weight: FontWeight) = Font(
    R.font.inter_variable,
    weight = weight,
    variationSettings = FontVariation.Settings(FontVariation.weight(weight.weight)),
)

@OptIn(ExperimentalTextApi::class)
private fun mono(weight: FontWeight) = Font(
    R.font.jetbrains_mono_variable,
    weight = weight,
    variationSettings = FontVariation.Settings(FontVariation.weight(weight.weight)),
)

val InterFamily = FontFamily(
    inter(FontWeight.Thin), inter(FontWeight.ExtraLight), inter(FontWeight.Light), inter(FontWeight.Normal),
    inter(FontWeight.Medium), inter(FontWeight.SemiBold), inter(FontWeight.Bold),
)
val MonoFamily = FontFamily(mono(FontWeight.Normal), mono(FontWeight.Medium))

private const val TNUM = "tnum, cv11"

@Immutable
data class ZTypography(
    /** "已连接" status headline. */
    val status: TextStyle,
    /** 2.8 MB/s, 13,109,802 — hero numbers. */
    val hero: TextStyle,
    /** 1.8 GB today card. */
    val display: TextStyle,
    /** Card numbers (512 节点). */
    val number: TextStyle,
    val title: TextStyle,
    val headline: TextStyle,
    val body: TextStyle,
    val bodyStrong: TextStyle,
    val callout: TextStyle,
    val footnote: TextStyle,
    val caption: TextStyle,
    val sectionLabel: TextStyle,
    val button: TextStyle,
    val mono: TextStyle,
    val monoSmall: TextStyle,
    val numeric: TextStyle,
) {
    companion object {
        private fun s(size: Int, weight: FontWeight, line: Int? = null, track: TextUnit = 0.em, features: String? = null, family: FontFamily = InterFamily) =
            TextStyle(
                fontFamily = family, fontWeight = weight, fontSize = size.sp,
                lineHeight = (line ?: (size * 1.3f).toInt()).sp, letterSpacing = track, fontFeatureSettings = features,
            )

        val default = ZTypography(
            status = s(44, FontWeight.ExtraLight, 50, (-0.01).em),
            hero = s(56, FontWeight.ExtraLight, 60, (-0.02).em, TNUM),
            display = s(88, FontWeight.Thin, 92, (-0.03).em, TNUM),
            number = s(30, FontWeight.Light, 36, (-0.01).em, TNUM),
            title = s(30, FontWeight.SemiBold, 36, (-0.01).em),
            headline = s(17, FontWeight.SemiBold, 22),
            body = s(16, FontWeight.Normal, 22),
            bodyStrong = s(16, FontWeight.Medium, 22),
            callout = s(15, FontWeight.Normal, 20),
            footnote = s(13, FontWeight.Normal, 18),
            caption = s(12, FontWeight.Normal, 16),
            sectionLabel = s(14, FontWeight.Medium, 18),
            button = s(15, FontWeight.SemiBold, 20),
            mono = s(14, FontWeight.Normal, 20, family = MonoFamily, features = "zero"),
            monoSmall = s(12, FontWeight.Normal, 16, family = MonoFamily, features = "zero"),
            numeric = s(15, FontWeight.Normal, 20, features = TNUM),
        )
    }
}
