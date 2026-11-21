package com.zephyr.app.vpn

import com.zephyr.app.ui.common.sceneName
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
                NotificationChannel(CH_VPN, ctx.getString(R.string.notif_channel_vpn), NotificationManager.IMPORTANCE_LOW).apply {
                    description = ctx.getString(R.string.notif_channel_vpn_desc); setShowBadge(false)
                },
                NotificationChannel(CH_ALERTS, ctx.getString(R.string.notif_channel_alerts), NotificationManager.IMPORTANCE_DEFAULT).apply {
                    description = ctx.getString(R.string.notif_channel_alerts_desc)
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
            .setColor(com.zephyr.design.tokens.ZAccent.valueOf(accent.name).colorDark.toArgb())
        if (connecting || c == null) {
            return b.setContentTitle(ctx.getString(R.string.app_name)).setContentText(ctx.getString(R.string.common_status_connecting_ellipsis)).build()
        }
        val down = t?.let { ZFormat.rate(it.downBps) } ?: ("0" to "B")
        val up = t?.let { ZFormat.rate(it.upBps) } ?: ("0" to "B")
        val speed = "${down.first} ${down.second}/s ↓ · ${up.first} ${up.second}/s ↑"
        val route = if (c.mode == ProxyMode.GLOBAL) ctx.getString(R.string.notif_route_global, globalNode ?: ctx.getString(R.string.notif_route_global_any)) else scenes.joinToString(" · ") { "${ctx.resources.sceneName(it)} ${it.selected.name}" }
        // Uptime is a system chronometer (review W-P2-1): it ticks without us re-posting the notification every second.
        c.since?.let { b.setWhen(it).setShowWhen(true).setUsesChronometer(true) }
        return b
            .setContentTitle(ctx.getString(R.string.app_name))
            .setContentText(speed)
            .setStyle(NotificationCompat.BigTextStyle().bigText("$speed\n$route"))
            .addAction(0, ctx.getString(R.string.common_disconnect), action(ctx, ZephyrVpnService.ACTION_DISCONNECT))
            .addAction(
                0,
                ctx.getString(if (c.mode == ProxyMode.GLOBAL) R.string.notif_action_rule else R.string.notif_action_global),
                action(ctx, ZephyrVpnService.ACTION_TOGGLE_MODE),
            )
            .build()
    }

    /**
     * Contract §16.a⑤: the tunnel was dropped on a trusted Wi‑Fi and on-demand will bring it back when the device
     * leaves it. The service stays in the foreground (that is what keeps the network watch alive); 连接 connects here
     * anyway, 断开连接 is a manual disconnect (pauses on-demand until the next manual connect).
     */
    fun pausedOnTrusted(ctx: Context, ssid: String?, accent: com.zephyr.engine.Accent): Notification {
        val open = PendingIntent.getActivity(ctx, 0, Intent(ctx, MainActivity::class.java), PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        return NotificationCompat.Builder(ctx, CH_VPN)
            .setSmallIcon(R.drawable.ic_stat_zephyr)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setSilent(true)
            .setShowWhen(false)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE)
            .setContentIntent(open)
            .setColor(com.zephyr.design.tokens.ZAccent.valueOf(accent.name).colorDark.toArgb())
            .setContentTitle(ctx.getString(R.string.app_name))
            .setContentText(ctx.getString(R.string.notif_paused_trusted, ssid ?: ""))
            .addAction(0, ctx.getString(R.string.common_connect), action(ctx, ZephyrVpnService.ACTION_CONNECT))
            .addAction(0, ctx.getString(R.string.common_disconnect), action(ctx, ZephyrVpnService.ACTION_DISCONNECT))
            .build()
    }

    /** "Orbit 将于 11月9日 到期" · "剩余 12.0 GB" (no traffic info: title only). Tap → subscriptions (§16.e ⑤). */
    fun expiry(ctx: Context, name: String, date: String, remaining: String?): Notification {
        val open = PendingIntent.getActivity(
            ctx, ID_EXPIRY,
            Intent(ctx, MainActivity::class.java).setAction(MainActivity.ACTION_OPEN_SUBSCRIPTIONS).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        return NotificationCompat.Builder(ctx, CH_ALERTS)
            .setSmallIcon(R.drawable.ic_stat_zephyr)
            .setContentTitle(ctx.getString(R.string.notif_expiry_title, name, date))
            .apply { if (remaining != null) setContentText(ctx.getString(R.string.notif_expiry_text, remaining)) }
            .setContentIntent(open)
            .setAutoCancel(true)
            .build()
    }

    private fun action(ctx: Context, a: String): PendingIntent =
        PendingIntent.getService(ctx, a.hashCode(), Intent(ctx, ZephyrVpnService::class.java).setAction(a), PendingIntent.FLAG_IMMUTABLE)
}
