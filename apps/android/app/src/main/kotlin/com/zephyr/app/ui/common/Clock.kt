package com.zephyr.app.ui.common

import androidx.compose.runtime.staticCompositionLocalOf

/** Wall clock for relative-time copy ("2 小时前", "26 天后到期"); screenshot tests pin it. */
val LocalNow = staticCompositionLocalOf<() -> Long> { System::currentTimeMillis }
