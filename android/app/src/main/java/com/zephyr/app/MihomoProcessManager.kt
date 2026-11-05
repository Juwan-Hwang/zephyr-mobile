package com.zephyr.app

import android.content.Context
import android.util.Log
import uniffi.zephyr_core.*
import java.io.File

/**
 * Android implementation of the [ProcessManager] UniFFI callback interface.
 *
 * Starts mihomo as a direct child process (no VPN Service).
 * mihomo runs as a regular proxy server (HTTP/SOCKS), and the app
 * communicates with it via the RESTful API on localhost.
 *
 * VPN-based TUN mode is not supported on Android because mihomo's TUN
 * implementation requires netlink sockets which are banned for non-root
 * apps. Instead, users can set system proxy to mihomo's mixed-port.
 */
class MihomoProcessManager(private val context: Context) : ProcessManager {

    companion object {
        const val TAG = "MihomoProcessManager"
        private var mihomoProcess: Process? = null
        private var outputReaderThread: Thread? = null
    }

    /**
     * Start mihomo as a direct child process.
     *
     * No VPN Service or TUN — mihomo runs as a regular proxy server.
     */
    override fun startCore(configPath: String): CoreStartResult {
        Log.i(TAG, "startCore: configPath=$configPath")

        // Parse the config to extract secret and ports
        val configFile = File(configPath)
        val configContent = configFile.readText()
        val secret = extractSecretFromYaml(configContent) ?: ""
        val apiPort = parseExternalControllerPort(configContent).toInt()
        val mixedPort = extractMixedPortFromYaml(configContent).toInt()

        // Kill any existing process
        if (mihomoProcess != null) {
            stopCore()
            Thread.sleep(200)
        }

        // Use mihomo from nativeLibraryDir (installed as libmihomo.so via jniLibs).
        // This directory allows exec on Android 10+ (unlike filesDir which is blocked by WRIX).
        val coreDir = File(context.filesDir, "core")
        coreDir.mkdirs()
        val nativeLibDir = File(context.applicationInfo.nativeLibraryDir)
        val mihomoExe = File(nativeLibDir, "libmihomo.so")
        if (!mihomoExe.exists()) {
            throw AppException.IoException("mihomo binary not found in nativeLibraryDir: ${mihomoExe.absolutePath}")
        }

        val cmd = arrayOf(
            mihomoExe.absolutePath,
            "-d", coreDir.absolutePath,
            "-f", configPath,
        )

        Log.d(TAG, "Starting mihomo: ${cmd.joinToString(" ")}")

        val processBuilder = ProcessBuilder(*cmd)
            .directory(coreDir)
            .redirectErrorStream(true)

        val process = processBuilder.start()
        mihomoProcess = process

        // Drain stdout/stderr in a background thread to prevent process blocking
        outputReaderThread = Thread {
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

        // Wait for mihomo to start (check if process is still alive and API is reachable)
        val maxWaitMs = 5000L
        val pollIntervalMs = 200L
        var waited = 0L
        while (waited < maxWaitMs) {
            if (!process.isAlive) {
                val exitCode = process.exitValue()
                mihomoProcess = null
                throw AppException.IoException("mihomo exited immediately with code $exitCode")
            }
            // Try to connect to the API to confirm mihomo is ready
            try {
                val url = java.net.URL("http://127.0.0.1:$apiPort/version")
                val conn = url.openConnection() as java.net.HttpURLConnection
                conn.requestMethod = "GET"
                conn.setRequestProperty("Authorization", "Bearer $secret")
                conn.connectTimeout = 500
                conn.readTimeout = 500
                val response = conn.responseCode
                conn.disconnect()
                if (response == 200 || response == 401) {
                    Log.i(TAG, "mihomo API is ready (response=$response)")
                    break
                }
            } catch (_: Exception) {
                // API not ready yet, keep waiting
            }
            Thread.sleep(pollIntervalMs)
            waited += pollIntervalMs
        }

        if (!process.isAlive) {
            mihomoProcess = null
            throw AppException.IoException("mihomo process died during startup")
        }

        Log.i(TAG, "mihomo started successfully, apiPort=$apiPort, mixedPort=$mixedPort")

        return CoreStartResult(
            apiPort = apiPort.toUShort(),
            mixedPort = mixedPort.toUShort(),
            secret = secret,
            configPath = configPath,
        )
    }

    /**
     * Stop the mihomo process.
     */
    override fun stopCore() {
        Log.i(TAG, "stopCore")
        mihomoProcess?.let { process ->
            try {
                process.destroy()
                val exited = process.waitFor()
                Log.d(TAG, "mihomo exited with code $exited")
            } catch (e: Exception) {
                Log.w(TAG, "Error stopping mihomo process", e)
                try { process.destroyForcibly() } catch (_: Exception) {}
            }
            mihomoProcess = null
        }
        outputReaderThread?.let {
            try { it.interrupt() } catch (_: Exception) {}
            outputReaderThread = null
        }
    }

    /**
     * Check if the mihomo process is currently running.
     */
    override fun isRunning(): Boolean {
        return mihomoProcess?.isAlive == true
    }

    /**
     * Get the version of the mihomo binary by executing `mihomo -v`.
     */
    override fun getVersion(): String {
        val nativeLibDir = File(context.applicationInfo.nativeLibraryDir)
        val mihomoExe = File(nativeLibDir, "libmihomo.so")

        if (!mihomoExe.exists()) {
            throw AppException.IoException("mihomo binary not found at ${mihomoExe.absolutePath}")
        }

        return try {
            val process = ProcessBuilder(mihomoExe.absolutePath, "-v")
                .redirectErrorStream(true)
                .start()

            val output = process.inputStream.bufferedReader().readText().trim()
            process.waitFor()

            if (process.exitValue() != 0) {
                throw AppException.IoException("mihomo -v failed: $output")
            }

            output
        } catch (e: AppException) {
            throw e
        } catch (e: Exception) {
            throw AppException.IoException("Failed to get mihomo version: ${e.message}")
        }
    }

    /**
     * Kill all core processes (force cleanup on app exit).
     */
    override fun killAll() {
        Log.i(TAG, "killAll")
        stopCore()
        // Also try to kill any remaining mihomo processes
        try {
            val process = Runtime.getRuntime().exec(arrayOf("pkill", "-f", "libmihomo.so"))
            process.waitFor()
        } catch (e: Exception) {
            Log.w(TAG, "pkill libmihomo.so failed (expected on non-rooted devices)", e)
        }
    }
}
