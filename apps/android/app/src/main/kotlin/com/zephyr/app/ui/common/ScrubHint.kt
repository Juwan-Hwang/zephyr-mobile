package com.zephyr.app.ui.common

import androidx.compose.runtime.staticCompositionLocalOf

/**
 * Whether the "左右滑动以切换地区" coach line has been retired, and how to retire it. Persisted in the app (review
 * H-P2-5: it used to come back every time Home recomposed from scratch); previews and screenshot tests keep the
 * default, which always shows it.
 */
class ScrubHint(val seen: Boolean, val markSeen: () -> Unit)

val LocalScrubHint = staticCompositionLocalOf { ScrubHint(seen = false, markSeen = {}) }
