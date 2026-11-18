package com.zephyr.app

import android.app.Application
import com.zephyr.app.di.AppGraph

class ZephyrApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        AppGraph.init(this)
        // SubscriptionWorker / midnight widget refresh are scheduled by SettingsStore once settings are loaded.
    }
}
