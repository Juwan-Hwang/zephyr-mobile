package com.zephyr.app.di

import java.io.File

/**
 * Issue #208 (QS tile → app exits, no log): the logs page's app lines live in memory, so a crash took its own reason
 * with it. The process-wide uncaught-exception handler writes the throwable to [file] synchronously before the
 * default handler kills the process; the next start reads it once into the logs page ([takeLine]) and deletes it.
 * Coroutine failures caught by [AppGraph.guard] go to the logs page directly and never reach this file.
 */
class CrashRecord(private val file: File) {

    /** Writes the crash; never throws (the process is dying, a second failure must not mask the first). */
    fun write(thread: String, t: Throwable, atMs: Long) {
        runCatching {
            file.parentFile?.mkdirs()
            file.writeText(format(thread, t, atMs))
        }
    }

    /** The recorded crash as one log line (null when there is none), deleting it so it is reported only once. */
    fun takeLine(): String? {
        val text = runCatching { if (file.isFile) file.readText() else null }.getOrNull()
        runCatching { file.delete() }
        return text?.takeIf { it.isNotBlank() }?.let { "previous run crashed: ${it.trim()}" }
    }

    companion object {
        const val FILE_NAME = "last-crash.txt"
        /** Frames kept per throwable: enough to see the call site, short enough for one logs-page row. */
        const val MAX_FRAMES = 12
        private const val MAX_CAUSES = 3

        /** `<epochMs> [thread] Type: message` + the top frames, then up to [MAX_CAUSES] causes the same way. */
        fun format(thread: String, t: Throwable, atMs: Long): String = buildString {
            append(atMs).append(" [").append(thread).append("] ")
            var cur: Throwable? = t
            var depth = 0
            val seen = HashSet<Throwable>()
            while (cur != null && depth <= MAX_CAUSES && seen.add(cur)) {
                if (depth > 0) append("\ncaused by: ")
                append(cur.javaClass.name)
                cur.message?.let { append(": ").append(it) }
                cur.stackTrace.take(MAX_FRAMES).forEach { append("\n  at ").append(it) }
                cur = cur.cause
                depth++
            }
        }

        /**
         * Installs [record] in front of the existing default handler (which still crashes the process as before,
         * so the system's crash dialog / logcat `FATAL EXCEPTION` line are unchanged).
         */
        fun install(record: CrashRecord, clock: () -> Long = System::currentTimeMillis) {
            val previous = Thread.getDefaultUncaughtExceptionHandler()
            Thread.setDefaultUncaughtExceptionHandler { th, e ->
                record.write(th.name, e, clock())
                previous?.uncaughtException(th, e)
            }
        }
    }
}
