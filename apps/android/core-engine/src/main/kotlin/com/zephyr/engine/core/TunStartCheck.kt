package com.zephyr.engine.core

/**
 * Issue #1 (S25 Ultra, Android 16, non-root, debug e244006): mihomo logged
 * `Start TUN listening error: build android rules: read packages list: open /data/system/packages.xml: permission denied`
 * and still returned success from `zm_start` — `listener.ReCreateTun` only logs a TUN failure and carries on with the
 * other listeners, so the app would sit "connected" on a tun nobody reads. These helpers make that visible:
 *
 * - [outcome] reads the core's log lines written after `zm_start` for the TUN result;
 * - [configProblems] checks the generated `tun:` block for what a VpnService tun needs (system fd, mihomo does not
 *   route, no per-app fields — per-app routing is `VpnService.Builder.addAllowed/DisallowedApplication`).
 *
 * Note: in mihomo v1.19.33 (`listener/sing_tun/server_android.go`, build tag `android && !cmfa`) `buildAndroidRules`
 * reads /data/system/packages.xml on every TUN start whatever the config says, so no config can avoid that read;
 * the fix is in the mihomo build (mihomo-mobile / tools), see the PR. The config check still guards the fields that
 * would make it matter even after that fix (include/exclude-package need the package list).
 */
object TunStartCheck {
    /** mihomo `listener.ReCreateTun`: `log.Errorln("Start TUN listening error: %s", err)`. */
    const val TUN_ERROR = "Start TUN listening error:"
    /** mihomo `listener.ReCreateTun`: `log.Infoln("[TUN] Tun adapter listening at: %s", …)`. */
    const val TUN_OK = "[TUN] Tun adapter listening at"
    /** Prefix of the error the bridge reports (kept `core_crashed`: the kernel did not bring the tun up). */
    const val PREFIX = "tun start failed: "

    sealed interface Outcome {
        data object Listening : Outcome
        data class Failed(val reason: String) : Outcome
    }

    /** First TUN verdict among [messages] (oldest first), or null while mihomo has not logged one yet. */
    fun outcome(messages: List<String>): Outcome? {
        for (m in messages) {
            val i = m.indexOf(TUN_ERROR)
            if (i >= 0) return Outcome.Failed(m.substring(i + TUN_ERROR.length).trim().ifEmpty { "unknown" })
            if (m.contains(TUN_OK)) return Outcome.Listening
        }
        return null
    }

    /** The bridge's error text for a failed TUN start. */
    fun message(f: Outcome.Failed): String = PREFIX + f.reason

    /** Keys that make sing-tun look up Android packages / users, or route on its own. */
    val FORBIDDEN_KEYS = listOf(
        "include-package", "exclude-package", "include-uid", "include-uid-range", "exclude-uid", "exclude-uid-range",
        "include-android-user", "route-address-set", "route-exclude-address-set", "auto-redirect",
    )

    /**
     * What is wrong with the top-level `tun:` block of a generated mihomo config for the VpnService path; empty = fine.
     * Expects the fd [fd], `auto-route: false`, `auto-detect-interface: false`, `mtu` = [mtu] (same value the
     * `VpnService.Builder` got) and none of [FORBIDDEN_KEYS]. Block-style YAML (what core-mobile emits).
     */
    fun configProblems(config: String, fd: Int, mtu: Int): List<String> {
        val block = tunBlock(config) ?: return listOf("no tun block")
        val keys = block.mapNotNull { line -> KEY.find(line)?.let { it.groupValues[1] to it.groupValues[2].trim() } }.toMap()
        val out = mutableListOf<String>()
        if (keys["enable"] != "true") out += "tun.enable is not true"
        if (keys["file-descriptor"] != fd.toString()) out += "tun.file-descriptor is ${keys["file-descriptor"]}, expected $fd"
        if (keys["auto-route"] != "false") out += "tun.auto-route is ${keys["auto-route"]}, expected false"
        if (keys["auto-detect-interface"] != "false") out += "tun.auto-detect-interface is ${keys["auto-detect-interface"]}, expected false"
        if (keys["mtu"] != mtu.toString()) out += "tun.mtu is ${keys["mtu"]}, expected $mtu"
        FORBIDDEN_KEYS.filter { it in keys }.forEach { out += "tun.$it must not be set" }
        return out
    }

    /** Lines of the top-level `tun:` mapping (its direct children only), or null when absent. */
    private fun tunBlock(config: String): List<String>? {
        val lines = config.lines()
        val start = lines.indexOfFirst { it.trimEnd() == "tun:" }
        if (start < 0) return null
        val body = lines.drop(start + 1).takeWhile { it.isBlank() || it.startsWith(" ") || it.startsWith("\t") || it.startsWith("- ") }
            .filter { it.isNotBlank() }
        val indent = body.firstOrNull()?.let { it.length - it.trimStart().length } ?: return emptyList()
        return body.filter { it.length - it.trimStart().length == indent && !it.trimStart().startsWith("- ") }
    }

    private val KEY = Regex("""^\s*([A-Za-z0-9_-]+):\s*(.*?)\s*$""")
}
