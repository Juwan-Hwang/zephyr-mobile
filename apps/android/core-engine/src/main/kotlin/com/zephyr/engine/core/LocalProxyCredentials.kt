package com.zephyr.engine.core

import java.io.File
import java.security.KeyStore
import java.security.SecureRandom
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/**
 * Local proxy credential (contract §16.g ①, audit U9): `zephyr:<24>` from an alphabet without the look-alikes
 * 0 O 1 l I, drawn with [SecureRandom]. Same format on iOS.
 */
object LocalProxyCredential {
    const val USER = "zephyr"
    const val ALPHABET = "abcdefghijkmnpqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789"
    const val LENGTH = 24
    private val FORMAT = Regex("^$USER:[$ALPHABET]{$LENGTH}$")

    fun generate(random: SecureRandom = SecureRandom()): String =
        "$USER:" + CharArray(LENGTH) { ALPHABET[random.nextInt(ALPHABET.length)] }.concatToString()

    fun isValid(credential: String): Boolean = FORMAT.matches(credential)

    fun password(credential: String): String = credential.substringAfter(':')

    /** What 复制 puts on the clipboard: `http://zephyr:<pw>@127.0.0.1:<port>` / `socks5://…`. */
    fun url(scheme: String, credential: String, port: Int): String = "$scheme://$credential@127.0.0.1:$port"
}

/** Authenticated encryption for small secrets at rest. */
interface SecretBox {
    fun seal(plain: ByteArray): ByteArray
    fun open(sealed: ByteArray): ByteArray
}

/**
 * AES-256-GCM with a non-exportable key in the Android Keystore (no androidx.security-crypto, which is deprecated).
 * Layout: 12-byte IV ‖ ciphertext+tag. Throws on JVM / when the keystore is unavailable; callers handle that.
 */
class KeystoreSecretBox(private val alias: String = "zephyr.local-proxy") : SecretBox {
    private fun key(): SecretKey {
        val ks = KeyStore.getInstance(PROVIDER).apply { load(null) }
        (ks.getEntry(alias, null) as? KeyStore.SecretKeyEntry)?.let { return it.secretKey }
        val gen = KeyGenerator.getInstance("AES", PROVIDER)
        gen.init(
            android.security.keystore.KeyGenParameterSpec.Builder(
                alias,
                android.security.keystore.KeyProperties.PURPOSE_ENCRYPT or android.security.keystore.KeyProperties.PURPOSE_DECRYPT,
            )
                .setBlockModes(android.security.keystore.KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(android.security.keystore.KeyProperties.ENCRYPTION_PADDING_NONE)
                .setKeySize(256)
                .build(),
        )
        return gen.generateKey()
    }

    override fun seal(plain: ByteArray): ByteArray {
        val c = Cipher.getInstance(TRANSFORM).apply { init(Cipher.ENCRYPT_MODE, key()) }
        return c.iv + c.doFinal(plain)
    }

    override fun open(sealed: ByteArray): ByteArray {
        require(sealed.size > IV)
        val c = Cipher.getInstance(TRANSFORM).apply { init(Cipher.DECRYPT_MODE, key(), GCMParameterSpec(128, sealed, 0, IV)) }
        return c.doFinal(sealed, IV, sealed.size - IV)
    }

    private companion object {
        const val PROVIDER = "AndroidKeyStore"
        const val TRANSFORM = "AES/GCM/NoPadding"
        const val IV = 12
    }
}

/**
 * Keeps the credential sealed by [box] in `<dir>/local-proxy-credential.enc`. Builds before #208 kept it in plain
 * text at `<dir>/local-proxy-credential`: that value is read once, sealed, and the plain file deleted (E42), so
 * apps the user already configured keep working. The plain file is only deleted after the sealed copy is written.
 *
 * When the keystore cannot be used (never on a real device; JVM tests, broken vendor keystores) nothing is written
 * in plain text: the credential lives for this process only, and a legacy plain file is left as it was.
 * A sealed file that no longer opens (key gone, e.g. restored onto another device) is treated as absent.
 */
class LocalProxyCredentialStore(
    dir: File?,
    private val box: SecretBox?,
    private val generate: () -> String = { LocalProxyCredential.generate() },
) {
    private val legacy = dir?.let { File(it, LEGACY) }
    private val sealedFile = dir?.let { File(it, SEALED) }
    private var cached: String? = null

    @Synchronized
    fun get(): String {
        cached?.let { return it }
        val v = readSealed()?.also { runCatching { legacy?.delete() } }
            ?: readLegacy()?.also { if (persist(it)) runCatching { legacy?.delete() } }
            ?: generate().also { persist(it) }
        cached = v
        return v
    }

    /** New password (§16.g `resetLocalProxyCredential`); the previous one is no longer accepted once reloaded. */
    @Synchronized
    fun reset(): String {
        var v = generate()
        while (v == cached) v = generate()
        persist(v)
        runCatching { legacy?.delete() }
        cached = v
        return v
    }

    /** Puts [previous] back after a failed hot reload (§16.b③ rollback). */
    @Synchronized
    fun restore(previous: String) {
        if (!LocalProxyCredential.isValid(previous)) return
        persist(previous)
        cached = previous
    }

    private fun readSealed(): String? {
        val f = sealedFile?.takeIf { it.isFile } ?: return null
        val b = box ?: return null
        return runCatching { String(b.open(f.readBytes()), Charsets.UTF_8) }.getOrNull()?.takeIf(LocalProxyCredential::isValid)
    }

    private fun readLegacy(): String? =
        legacy?.takeIf { it.isFile }?.let { f -> runCatching { f.readText().trim() }.getOrNull() }?.takeIf(LocalProxyCredential::isValid)

    private fun persist(v: String): Boolean {
        val f = sealedFile ?: return false
        val b = box ?: return false
        return runCatching {
            val bytes = b.seal(v.toByteArray(Charsets.UTF_8))
            val tmp = File(f.parentFile, "$SEALED.tmp")
            tmp.writeBytes(bytes)
            if (!tmp.renameTo(f)) { f.delete(); check(tmp.renameTo(f)) }
        }.isSuccess
    }

    companion object {
        const val LEGACY = "local-proxy-credential"
        const val SEALED = "local-proxy-credential.enc"
    }
}
