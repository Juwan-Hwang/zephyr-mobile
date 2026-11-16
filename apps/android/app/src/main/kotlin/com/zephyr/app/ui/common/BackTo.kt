package com.zephyr.app.ui.common

import androidx.annotation.StringRes
import com.zephyr.app.R
import kotlinx.serialization.Serializable

/** Where a page's "‹" link returns to. Routes carry this, not a label, so the link follows the App's language. */
@Serializable
enum class BackTo(@StringRes val label: Int) {
    LIBRARY(R.string.common_library),
    HOME(R.string.common_home),
    SETTINGS(R.string.common_settings),
}
