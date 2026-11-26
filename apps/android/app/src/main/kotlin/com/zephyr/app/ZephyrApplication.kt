package com.zephyr.app

import android.app.Application
import com.zephyr.app.di.AppGraph

class ZephyrApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        // Issue #208: an uncaught exception is written to a file before the process dies; the next start shows it in 日志.
        com.zephyr.app.di.CrashRecord.install(com.zephyr.app.di.CrashRecord(java.io.File(filesDir, com.zephyr.app.di.CrashRecord.FILE_NAME)))
        AppGraph.init(this)
        // SubscriptionWorker / midnight widget refresh are scheduled by SettingsStore once settings are loaded.
    }
}
