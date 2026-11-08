package com.zephyr.engine.core

import java.io.BufferedInputStream
import java.io.InputStream
import java.net.InetSocketAddress
import java.net.Socket
import java.net.URI
import java.util.Base64
import javax.net.ssl.SSLSocket
import javax.net.ssl.SSLSocketFactory

/**
 * HTTPS probe through mihomo's loopback mixed port (contract §14.z ①). The app itself is excluded from its own
 * VPN (an in-process core must not loop back into the tun), so service/exit probes go through the proxy port
 * instead: CONNECT with Basic auth, then TLS to the real host. That way a probe follows the same rules,
 * scenes and per-app exceptions as the user's traffic. Blocking; call on an IO dispatcher.
 */
object ProxyProbe {
    data class Response(val status: Int, val body: String)

    fun request(url: String, port: Int, auth: String?, method: String = "GET", timeoutMs: Int = 6_000, maxBody: Int = 4_096): Response? = runCatching {
        val u = URI(url)
        val host = u.host ?: return null
        val path = (u.rawPath?.ifEmpty { "/" } ?: "/") + (u.rawQuery?.let { "?$it" } ?: "")
        Socket().use { raw ->
            raw.soTimeout = timeoutMs
            raw.connect(InetSocketAddress("127.0.0.1", port), timeoutMs)
            val out = raw.getOutputStream()
            val proxyAuth = auth?.let { "Proxy-Authorization: Basic " + Base64.getEncoder().encodeToString(it.toByteArray()) + "\r\n" } ?: ""
            out.write("CONNECT $host:443 HTTP/1.1\r\nHost: $host:443\r\n$proxyAuth\r\n".toByteArray())
            out.flush()
            val input = BufferedInputStream(raw.getInputStream())
            val connect = statusOf(readHead(input)) ?: return null
            if (connect != 200) return null
            val tls = (SSLSocketFactory.getDefault() as SSLSocketFactory).createSocket(raw, host, 443, true) as SSLSocket
            tls.use { s ->
                s.soTimeout = timeoutMs
                s.startHandshake()
                s.outputStream.write("$method $path HTTP/1.1\r\nHost: $host\r\nUser-Agent: Zephyr\r\nAccept: */*\r\nConnection: close\r\n\r\n".toByteArray())
                s.outputStream.flush()
                val inp = BufferedInputStream(s.inputStream)
                val status = statusOf(readHead(inp)) ?: return null
                val body = if (method == "HEAD") "" else String(readUpTo(inp, maxBody))
                Response(status, body)
            }
        }
    }.getOrNull()

    private fun readHead(input: InputStream): String {
        val sb = StringBuilder()
        while (sb.length < 16_384) {
            val b = input.read()
            if (b < 0) break
            sb.append(b.toChar())
            if (sb.endsWith("\r\n\r\n")) break
        }
        return sb.toString()
    }

    private fun statusOf(head: String): Int? = head.lineSequence().firstOrNull()?.split(' ')?.getOrNull(1)?.toIntOrNull()

    private fun readUpTo(input: InputStream, max: Int): ByteArray {
        val buf = ByteArray(max); var n = 0
        while (n < max) { val r = input.read(buf, n, max - n); if (r < 0) break; n += r }
        return buf.copyOf(n)
    }

    /** Status rule from §14.z: reachable when the service answered below 500 and not 403 (geo-block). */
    fun serviceOk(r: Response?): Boolean = r != null && r.status < 500 && r.status != 403
}
