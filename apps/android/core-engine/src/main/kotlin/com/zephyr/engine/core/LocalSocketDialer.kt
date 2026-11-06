package com.zephyr.engine.core

import android.net.LocalSocket
import android.net.LocalSocketAddress
import java.io.File
import java.io.InputStream
import java.io.OutputStream

/** Dials mihomo's `external-controller-unix` socket (filesystem namespace, app-private dir). */
class LocalSocketDialer(private val path: File, private val timeoutMs: Int = 8_000) : MihomoRest.Dialer {
    override fun dial(): MihomoRest.Conn {
        val s = LocalSocket()
        try {
            s.connect(LocalSocketAddress(path.path, LocalSocketAddress.Namespace.FILESYSTEM))
            s.soTimeout = timeoutMs
        } catch (t: Throwable) { s.close(); throw t }
        return object : MihomoRest.Conn {
            override val input: InputStream = s.inputStream
            override val output: OutputStream = s.outputStream
            override fun close() = s.close()
        }
    }
}
