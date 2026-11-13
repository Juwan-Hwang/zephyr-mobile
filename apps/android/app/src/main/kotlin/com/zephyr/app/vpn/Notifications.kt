package com.zephyr.app.vpn

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import androidx.core.app.NotificationCompat
import com.zephyr.app.MainActivity
import com.zephyr.app.R
import com.zephyr.design.format.ZFormat
import androidx.compose.ui.graphics.toArgb
import com.zephyr.design.theme.darkVariant
import com.zephyr.engine.ConnectionState
import com.zephyr.engine.ProxyMode
import com.zephyr.engine.Scene
import com.zephyr.engine.TrafficSample

/**
 * Ongoing notification copy follows prototype `and`:
 * title "Zephyr · 2:14:07", text "2.8 MB/s ↓ · 194 KB/s ↑", big text adds "AI 东京 03 · 视频 香港 HKT · 其他 TW-Fixed-01",
 * actions 断开连接 / 全局模式. Silent, low importance, no badge. Uptime is a chronometer; the speed line is re-posted
 * only while the screen is on and at most every [MIN_POST_MS].
 */
object Notifications {
    const val CH_VPN = "vpn"
    const val CH_ALERTS = "alerts"
    const val ID_ONGOING = 1
    const val ID_EXPIRY = 2
    const val MIN_POST_MS = 2_000L

    fun ensureChannels(ctx: Context) {
        val nm = ctx.getSystemService(NotificationManager::class.java)
        nm.createNotificationChannels(
            listOf(
                NotificationChannel(CH_VPN, ctx.getString(R.string.channel_vpn), NotificationManager.IMPORTANCE_LOW).apply {
                    description = ctx.getString(R.string.channel_vpn_desc); setShowBadge(false)
                },
                NotificationChannel(CH_ALERTS, ctx.getString(R.string.channel_alerts), NotificationManager.IMPORTANCE_DEFAULT).apply {
                    description = ctx.getString(R.string.channel_alerts_desc)
                },
            ),
        )
    }

    fun ongoing(
        ctx: Context, c: ConnectionState?, t: TrafficSample?, scenes: List<Scene>, connecting: Boolean,
        accent: com.zephyr.engine.Accent = com.zephyr.engine.Accent.BLUE, globalNode: String? = null,
    ): Notification {
        val open = PendingIntent.getActivity(ctx, 0, Intent(ctx, MainActivity::class.java), PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        val b = NotificationCompat.Builder(ctx, CH_VPN)
            .setSmallIcon(R.drawable.ic_stat_zephyr)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setSilent(true)
            .setShowWhen(false)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE)
            .setContentIntent(open)
            // Follows the App's accent (review W-P2-4).
            .setColor(com.zephyr.design.tokens.ZAccent.valueOf(accent.name).darkVariant().toArgb())
        if (connecting || c == null) {
            return b.setContentTitle("Zephyr").setContentText("连接中…").build()
        }
        val down = t?.let { ZFormat.rate(it.downBps) } ?: ("0" to "B")
        val up = t?.let { ZFormat.rate(it.upBps) } ?: ("0" to "B")
        val speed = "${down.first} ${down.second}/s ↓ · ${up.first} ${up.second}/s ↑"
        val route = if (c.mode == ProxyMode.GLOBAL) "全局 · ${globalNode ?: "所有流量经由同一节点"}" else scenes.joinToString(" · ") { "${it.name} ${it.selected.name}" }
        // Uptime is a system chronometer (review W-P2-1): it ticks without us re-posting the notification every second.
        c.since?.let { b.setWhen(it).setShowWhen(true).setUsesChronometer(true) }
        return b
            .setContentTitle("Zephyr")
            .setContentText(speed)
            .setStyle(NotificationCompat.BigTextStyle().bigText("$speed\n$route"))
            .addAction(0, ctx.getString(R.string.action_disconnect), action(ctx, ZephyrVpnService.ACTION_DISCONNECT))
            .addAction(
                0,
                ctx.getString(if (c.mode == ProxyMode.GLOBAL) R.string.action_rule else R.string.action_global),
                action(ctx, ZephyrVpnService.ACTION_TOGGLE_MODE),
            )
            .build()
    }

    /** "Orbit 将于 11月9日 到期 · 剩余 12.0 GB" alert. */
    fun expiry(ctx: Context, name: String, date: String, remaining: String): Notification =
        NotificationCompat.Builder(ctx, CH_ALERTS)
            .setSmallIcon(R.drawable.ic_stat_zephyr)
            .setContentTitle("$name 将于 $date 到期")
            .setContentText("剩余 $remaining")
            .setAutoCancel(true)
            .build()

    private fun action(ctx: Context, a: String): PendingIntent =
        PendingIntent.getService(ctx, a.hashCode(), Intent(ctx, ZephyrVpnService::class.java).setAction(a), PendingIntent.FLAG_IMMUTABLE)
}
