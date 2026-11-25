package com.zephyr.app.vpn

import android.content.Context
import java.io.File
import java.io.InputStream

/**
 * Contract §20.d / docs/geodata.md: the APK ships a pinned geodata snapshot in `assets/geodata/` (geoip.metadb +
 * GeoSite.dat, fetched at build time by tools/fetch-geodata.sh). Before mihomo starts, each bundled file is copied
 * into its home dir (`filesDir/mihomo/`) when a file of that name is not there yet — first launch, after clearing
 * data, or after an upgrade that adds a file. An existing file is never overwritten: mihomo's geo-auto-update may
 * have refreshed it. Each copy goes to a temp name first and is renamed into place, so a crash mid-copy never
 * leaves a truncated file under the real name.
 */
object BundledGeodata {
    const val ASSET_DIR = "geodata"
    internal const val TMP_SUFFIX = ".zgtmp"

    /** Names of the files packaged under `assets/geodata/` (empty when the build had no snapshot). */
    fun bundled(ctx: Context): List<String> =
        runCatching { ctx.assets.list(ASSET_DIR)?.toList() }.getOrNull().orEmpty().filter { !it.startsWith(".") }.sorted()

    /** Copies the bundled files missing from [home]; returns the names copied. */
    fun install(ctx: Context, home: File): List<String> =
        installMissing(bundled(ctx), home, onError = { name, t -> android.util.Log.w("Zephyr", "geodata copy failed: $name: ${t.message}") }) {
            ctx.assets.open("$ASSET_DIR/$it")
        }

    /** True when every file in [names] is in [home] (then mihomo can start without downloading). */
    fun allPresent(names: List<String>, home: File): Boolean = names.isNotEmpty() && names.all { File(home, it).isFile }

    /**
     * Pure part of [install], for tests: for each name absent from [dir], stream [open] into `<name>.<n>.zgtmp`, then
     * rename to `<name>`. Present files are left alone; temp files left behind by an earlier crash are removed.
     * A file that fails to copy is skipped (mihomo then reports `geodata missing:` with the reason).
     */
    fun installMissing(
        names: List<String>, dir: File, onError: (String, Throwable) -> Unit = { _, _ -> }, open: (String) -> InputStream,
    ): List<String> {
        dir.mkdirs()
        dir.listFiles { f -> f.name.endsWith(TMP_SUFFIX) }?.forEach { it.delete() }
        val copied = mutableListOf<String>()
        for (name in names) {
            if (name.contains('/') || name.startsWith(".")) continue
            val dst = File(dir, name)
            if (dst.exists()) continue
            val tmp = File(dir, "$name.${System.nanoTime()}$TMP_SUFFIX")
            try {
                open(name).use { input -> tmp.outputStream().use { out -> input.copyTo(out, 64 * 1024); out.fd.sync() } }
                // Re-check right before the rename: never replace a file that appeared meanwhile.
                if (!dst.exists() && tmp.renameTo(dst)) copied += name
            } catch (t: Throwable) {
                onError(name, t)
            } finally {
                tmp.delete()
            }
        }
        return copied
    }
}
