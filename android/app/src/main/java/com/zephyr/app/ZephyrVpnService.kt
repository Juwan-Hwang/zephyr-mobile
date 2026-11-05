package com.zephyr.app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import android.net.VpnService
import android.os.Build
import android.os.ParcelFileDescriptor
import android.util.Log
import java.io.File
import java.io.FileOutputStream
import uniffi.zephyr_core.*

class ZephyrVpnService : VpnService() {

    companion object {
        const val TAG = "ZephyrVpnService"
        const val NOTIFICATION_CHANNEL_ID = "zephyr_vpn_channel"
        const val NOTIFICATION_ID = 1

        const val ACTION_START = "com.zephyr.app.START"
        const val ACTION_STOP = "com.zephyr.app.STOP"

        // Broadcast actions for communicating state back to the app
        const val ACTION_CORE_STARTED = "com.zephyr.app.CORE_STARTED"
        const val ACTION_CORE_STOPPED = "com.zephyr.app.CORE_STOPPED"
        const val ACTION_CORE_ERROR = "com.zephyr.app.CORE_ERROR"

        // Extras
        const val EXTRA_CONFIG_PATH = "configPath"
        const val EXTRA_SECRET = "secret"
        const val EXTRA_API_PORT = "apiPort"
        const val EXTRA_MIXED_PORT = "mixedPort"
        const val EXTRA_ERROR_MESSAGE = "errorMessage"

        // VPN interface parameters
        const val VPN_ADDRESS = "198.18.0.1"
        const val VPN_ROUTE = "0.0.0.0"
        const val VPN_MTU = 9000
        const val VPN_DNS_1 = "8.8.8.8"
        const val VPN_DNS_2 = "8.8.4.4"

        @Volatile
        var isRunning: Boolean = false
            private set

        @Volatile
        var currentSecret: String = ""
            private set

        @Volatile
        var currentApiPort: UShort = 0u
            private set

        @Volatile
        var currentMixedPort: UShort = 0u
            private set
    }

    private var vpnInterface: ParcelFileDescriptor? = null
    private var mihomoProcess: Process? = null
    private var configPath: String? = null

    // ── Lifecycle ──────────────────────────────────────────────────────────

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START -> {
                val cfgPath = intent.getStringExtra(EXTRA_CONFIG_PATH)
                val secret = intent.getStringExtra(EXTRA_SECRET) ?: ""
                val apiPort = intent.getIntExtra(EXTRA_API_PORT, 9090).toUShort()
                val mixedPort = intent.getIntExtra(EXTRA_MIXED_PORT, 7890).toUShort()

                if (cfgPath != null) {
                    startVpn(cfgPath, secret, apiPort, mixedPort)
                } else {
                    sendErrorBroadcast("No config path provided")
                    stopSelf()
                }
            }
            ACTION_STOP -> {
                stopVpn()
            }
            else -> {
                stopSelf()
            }
        }
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        stopVpn()
        super.onDestroy()
    }

    override fun onRevoke() {
        stopVpn()
        super.onRevoke()
    }

    // ── VPN interface ──────────────────────────────────────────────────────

    private fun buildVpnInterface(): ParcelFileDescriptor {
        return Builder()
            .setSession("Zephyr")
            .addAddress(VPN_ADDRESS, 16)
            .addRoute(VPN_ROUTE, 0)
            .addDnsServer(VPN_DNS_1)
            .addDnsServer(VPN_DNS_2)
            .setMtu(VPN_MTU)
            .establish()
            ?: throw IllegalStateException("Failed to create VPN interface")
    }

    // ── Start VPN + mihomo ─────────────────────────────────────────────────

    private fun startVpn(configPath: String, secret: String, apiPort: UShort, mixedPort: UShort) {
        if (isRunning) {
            Log.w(TAG, "VPN already running, stopping previous instance first")
            stopVpn()
        }

        try {
            // 1. Create TUN interface
            vpnInterface = buildVpnInterface()

            // 2. Write runtime config with TUN fd injected
            this.configPath = configPath
            val runConfigPath = writeRunConfigWithTun(configPath, vpnInterface!!.fd)

            // 3. Start foreground notification (must include serviceType for Android 14+)
            startForeground(NOTIFICATION_ID, buildNotification(),
                android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)

            // 4. Start mihomo process
            startMihomo(runConfigPath)

            // 5. Update state
            isRunning = true
            currentSecret = secret
            currentApiPort = apiPort
            currentMixedPort = mixedPort

            // 6. Notify app
            sendStartedBroadcast(apiPort, mixedPort, secret)

            Log.i(TAG, "VPN started successfully, apiPort=$apiPort, mixedPort=$mixedPort")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to start VPN", e)
            cleanup()
            sendErrorBroadcast("VPN start failed: ${e.message}")
            stopSelf()
        }
    }

    // ── Stop VPN + mihomo ───────────────────────────────────────────────────

    private fun stopVpn() {
        if (!isRunning && mihomoProcess == null && vpnInterface == null) return

        Log.i(TAG, "Stopping VPN")
        cleanup()

        isRunning = false
        currentSecret = ""
        currentApiPort = 0u
        currentMixedPort = 0u

        sendStoppedBroadcast()
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    private fun cleanup() {
        // Kill mihomo process
        mihomoProcess?.let {
            try {
                it.destroy()
                // Wait briefly for graceful shutdown
                val exited = it.waitFor()
                Log.d(TAG, "mihomo exited with code $exited")
            } catch (e: Exception) {
                Log.w(TAG, "Error stopping mihomo process", e)
                try { it.destroyForcibly() } catch (_: Exception) {}
            }
            mihomoProcess = null
        }

        // Close VPN interface
        vpnInterface?.let {
            try {
                it.close()
            } catch (e: Exception) {
                Log.w(TAG, "Error closing VPN interface", e)
            }
            vpnInterface = null
        }

        // Clean up run config
        configPath?.let { path ->
            try {
                val runConfig = File(filesDir, "core/run_config.yaml")
                if (runConfig.exists()) runConfig.delete()
            } catch (_: Exception) {}
        }
    }

    // ── Mihomo process management ──────────────────────────────────────────

    private fun startMihomo(runConfigPath: String) {
        val coreDir = File(filesDir, "core")
        val exe = File(coreDir, "zephyr-mihomo")

        // Use mihomo from nativeLibraryDir (installed as libmihomo.so via jniLibs).
        // This directory allows exec on Android 10+ (unlike filesDir which is blocked by WRIX).
        val nativeLibDir = File(applicationInfo.nativeLibraryDir)
        val mihomoExe = File(nativeLibDir, "libmihomo.so")
        if (!mihomoExe.exists()) {
            throw IllegalStateException("mihomo binary not found in nativeLibraryDir: ${mihomoExe.absolutePath}")
        }

        val cmd = arrayOf(
            mihomoExe.absolutePath,
            "-d", coreDir.absolutePath,
            "-f", runConfigPath,
        )

        Log.d(TAG, "Starting mihomo: ${cmd.joinToString(" ")}")

        val processBuilder = ProcessBuilder(*cmd)
            .directory(coreDir)
            .redirectErrorStream(true)

        val process = processBuilder.start()

        // Note: VpnService.protect() works on Socket/DatagramSocket, not Process.
        // mihomo on Android uses the TUN fd from the config and avoids routing
        // its own outbound connections through the VPN by using the
        // "auto-redirect" bypass mechanism. The TUN fd is passed via config
        // so mihomo knows which interface to read from, and its outbound
        // connections use the real network interface directly.

        // Start a thread to drain stdout/stderr to prevent process blocking
        Thread {
            try {
                val reader = process.inputStream.bufferedReader()
                var line: String?
                while (reader.readLine().also { line = it } != null) {
                    Log.d(TAG, "mihomo: $line")
                }
            } catch (e: Exception) {
                Log.d(TAG, "mihomo output reader finished: ${e.message}")
            }
        }.apply {
            name = "mihomo-output-reader"
            isDaemon = true
            start()
        }

        mihomoProcess = process

        // Check if process exits immediately
        Thread {
            try {
                Thread.sleep(300)
                if (process.isAlive) {
                    Log.i(TAG, "mihomo process started successfully")
                } else {
                    val exitCode = process.exitValue()
                    Log.e(TAG, "mihomo exited immediately with code $exitCode")
                    sendErrorBroadcast("mihomo exited immediately (code=$exitCode)")
                    stopVpn()
                }
            } catch (_: InterruptedException) {}
        }.apply {
            name = "mihomo-exit-check"
            isDaemon = true
            start()
        }
    }

    // ── Config management ──────────────────────────────────────────────────

    /**
     * Write the runtime config YAML to the core directory, injecting the TUN
     * file descriptor information for mihomo to use.
     *
     * On Android, mihomo reads the TUN fd from the config's `tun.fd` field.
     * We use UniFFI `injectTunFd()` which uses serde_yaml for reliable
     * injection (not regex), and also disables `auto-route` and
     * `auto-detect-interface` since VPN Service already handles routing.
     */
    private fun writeRunConfigWithTun(originalConfigPath: String, tunFd: Int): String {
        val coreDir = File(filesDir, "core")
        coreDir.mkdirs()

        val runConfigFile = File(coreDir, "run_config.yaml")

        // Read the original config
        val originalConfig = File(originalConfigPath).readText()

        // Step 1: Enable TUN in the config using UniFFI
        val configWithTun = updateTunInYaml(originalConfig, true)

        // Step 2: Inject TUN fd using UniFFI (reliable serde_yaml, not regex)
        // This also disables auto-route and auto-detect-interface for Android
        val configWithFd = injectTunFd(configWithTun, tunFd)

        FileOutputStream(runConfigFile).use { fos ->
            fos.write(configWithFd.toByteArray())
            fos.fd.sync() // Ensure data is written to disk
        }

        return runConfigFile.absolutePath
    }

    // ── Notification ───────────────────────────────────────────────────────

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                NOTIFICATION_CHANNEL_ID,
                "Zephyr VPN",
                NotificationManager.IMPORTANCE_LOW,
            ).apply {
                description = "Zephyr VPN service notification"
                setShowBadge(false)
                lockscreenVisibility = Notification.VISIBILITY_PRIVATE
            }
            val nm = getSystemService(NotificationManager::class.java)
            nm.createNotificationChannel(channel)
        }
    }

    private fun buildNotification(): Notification {
        val intent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP
        }
        val pendingIntent = PendingIntent.getActivity(
            this, 0, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        val stopIntent = Intent(this, ZephyrVpnService::class.java).apply {
            action = ACTION_STOP
        }
        val stopPendingIntent = PendingIntent.getService(
            this, 0, stopIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, NOTIFICATION_CHANNEL_ID)
                .setContentTitle("Zephyr")
                .setContentText("Zephyr VPN is running")
                .setSmallIcon(android.R.drawable.ic_lock_lock)
                .setContentIntent(pendingIntent)
                .addAction(
                    android.R.drawable.ic_menu_close_clear_cancel,
                    "Stop",
                    stopPendingIntent,
                )
                .setOngoing(true)
                .build()
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
                .setContentTitle("Zephyr")
                .setContentText("Zephyr VPN is running")
                .setSmallIcon(android.R.drawable.ic_lock_lock)
                .setContentIntent(pendingIntent)
                .setOngoing(true)
                .build()
        }
    }

    // ── Broadcast helpers ──────────────────────────────────────────────────

    private fun sendStartedBroadcast(apiPort: UShort, mixedPort: UShort, secret: String) {
        val intent = Intent(ACTION_CORE_STARTED).apply {
            putExtra(EXTRA_API_PORT, apiPort.toInt())
            putExtra(EXTRA_MIXED_PORT, mixedPort.toInt())
            putExtra(EXTRA_SECRET, secret)
            setPackage(packageName)
        }
        sendBroadcast(intent)
    }

    private fun sendStoppedBroadcast() {
        val intent = Intent(ACTION_CORE_STOPPED).apply {
            setPackage(packageName)
        }
        sendBroadcast(intent)
    }

    private fun sendErrorBroadcast(message: String) {
        val intent = Intent(ACTION_CORE_ERROR).apply {
            putExtra(EXTRA_ERROR_MESSAGE, message)
            setPackage(packageName)
        }
        sendBroadcast(intent)
    }
}
