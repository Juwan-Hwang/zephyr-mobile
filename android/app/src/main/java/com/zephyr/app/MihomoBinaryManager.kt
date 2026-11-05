package com.zephyr.app

import android.content.Context
import android.os.Build
import android.util.Log
import java.io.File
import java.io.FileOutputStream
import java.util.zip.GZIPInputStream

/**
 * Manages the mihomo core binary lifecycle.
 *
 * On first launch, extracts the mihomo binary from APK assets (bundled at build time)
 * to the app's private directory. This matches the desktop experience where mihomo
 * is bundled with the installer and works out of the box.
 */
object MihomoBinaryManager {

    private const val TAG = "MihomoBinaryManager"
    private const val CORE_DIR = "core"
    private const val BINARY_NAME = "zephyr-mihomo"

    // The version of mihomo bundled in assets (must match the downloaded binary)
    private const val BUNDLED_VERSION = "1.19.26"

    /**
     * Ensure the mihomo binary is extracted and ready to use.
     * Call this on app startup (e.g., in Application.onCreate or ViewModel init).
     *
     * @return the File pointing to the mihomo executable, or null on failure
     */
    fun ensureBinary(context: Context): File? {
        val coreDir = File(context.filesDir, CORE_DIR)
        val exe = File(coreDir, BINARY_NAME)
        val versionFile = File(coreDir, ".version")

        // Check if binary already exists and version matches
        if (exe.exists() && exe.canExecute()) {
            val existingVersion = try {
                versionFile.readText().trim()
            } catch (_: Exception) {
                ""
            }
            if (existingVersion == BUNDLED_VERSION) {
                // Ensure executable permission is set (may be lost after app update)
                if (exe.exists()) {
                    exe.setExecutable(true, false)
                    exe.setReadable(true, false)
                }
                Log.d(TAG, "mihomo v$BUNDLED_VERSION already installed at ${exe.absolutePath}")
                return exe
            }
            // Version mismatch — need to re-extract
            Log.i(TAG, "Updating mihomo from $existingVersion to $BUNDLED_VERSION")
            exe.delete()
            versionFile.delete()
        }

        // Extract from assets
        return try {
            extractFromAssets(context, coreDir, exe, versionFile)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to extract mihomo from assets", e)
            null
        }
    }

    /**
     * Get the path to the mihomo binary (without extracting).
     * Returns null if binary doesn't exist yet.
     */
    fun getBinaryPath(context: Context): String? {
        val exe = File(context.filesDir, "$CORE_DIR/$BINARY_NAME")
        return if (exe.exists()) exe.absolutePath else null
    }

    /**
     * Get the mihomo version currently installed.
     */
    fun getInstalledVersion(context: Context): String? {
        val versionFile = File(context.filesDir, "$CORE_DIR/.version")
        return try {
            if (versionFile.exists()) versionFile.readText().trim() else null
        } catch (_: Exception) {
            null
        }
    }

    private fun extractFromAssets(
        context: Context,
        coreDir: File,
        exe: File,
        versionFile: File
    ): File? {
        coreDir.mkdirs()

        // Determine which ABI to use
        // mihomo naming: mihomo-android-{arch}-v{version}.gz
        // arch: arm64-v8 (for arm64-v8a), amd64 (for x86_64), armv7 (for armeabi-v7a), 386 (for x86)
        val archName = when {
            Build.SUPPORTED_ABIS.contains("arm64-v8a") -> "arm64-v8"
            Build.SUPPORTED_ABIS.contains("x86_64") -> "amd64"
            Build.SUPPORTED_ABIS.contains("armeabi-v7a") -> "armv7"
            Build.SUPPORTED_ABIS.contains("x86") -> "386"
            else -> {
                Log.e(TAG, "Unsupported ABI: ${Build.SUPPORTED_ABIS.contentToString()}")
                return null
            }
        }

        // Try both .gz and non-.gz asset names
        // Gradle may auto-decompress .gz files during APK packaging
        val assetNames = listOf(
            "core/mihomo-android-$archName.gz",
            "core/mihomo-android-$archName",
            "core/mihomo-android-$archName-v$BUNDLED_VERSION.gz",
            "core/mihomo-android-$archName-v$BUNDLED_VERSION",
            // Legacy naming (older mihomo versions)
            "core/mihomo-android-${archName.substringBefore("-v8")}.gz",
            "core/mihomo-android-${archName.substringBefore("-v8")}",
        )

        for (assetName in assetNames) {
            try {
                Log.d(TAG, "Trying asset: $assetName")
                val inputStream = context.assets.open(assetName)
                val isGz = assetName.endsWith(".gz")

                if (isGz) {
                    GZIPInputStream(inputStream).use { gzIn ->
                        FileOutputStream(exe).use { out ->
                            val buf = ByteArray(8192)
                            var len: Int
                            while (gzIn.read(buf).also { len = it } != -1) {
                                out.write(buf, 0, len)
                            }
                        }
                    }
                } else {
                    inputStream.use { ins ->
                        FileOutputStream(exe).use { out ->
                            val buf = ByteArray(8192)
                            var len: Int
                            while (ins.read(buf).also { len = it } != -1) {
                                out.write(buf, 0, len)
                            }
                        }
                    }
                }

                exe.setExecutable(true, false)
                exe.setReadable(true, false)
                versionFile.writeText(BUNDLED_VERSION)
                Log.i(TAG, "mihomo v$BUNDLED_VERSION extracted from $assetName (${exe.length()} bytes)")
                return exe
            } catch (e: Exception) {
                Log.d(TAG, "Asset $assetName not found or extraction failed: ${e.message}")
                continue
            }
        }

        Log.e(TAG, "No mihomo binary found in assets for arch=$archName")
        return null
    }
}
