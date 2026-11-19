package com.zephyr.engine.core

import com.zephyr.engine.Settings
import com.zephyr.engine.mock.MockEngine
import kotlinx.coroutines.test.runTest
import java.io.File
import java.nio.file.Files
import java.security.SecureRandom
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec
import org.junit.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotEquals
import kotlin.test.assertTrue

/** Contract §16.g ① (audit U9): credential format, sealed storage and the plain-text migration (E42). */
class LocalProxyCredentialTest {
    /** Same AES-GCM layout as [KeystoreSecretBox], with a JVM key instead of the Android Keystore. */
    private class TestBox(private val key: SecretKey = KeyGenerator.getInstance("AES").apply { init(256) }.generateKey()) : SecretBox {
        override fun seal(plain: ByteArray): ByteArray {
            val c = Cipher.getInstance("AES/GCM/NoPadding").apply { init(Cipher.ENCRYPT_MODE, key) }
            return c.iv + c.doFinal(plain)
        }
        override fun open(sealed: ByteArray): ByteArray {
            val c = Cipher.getInstance("AES/GCM/NoPadding").apply { init(Cipher.DECRYPT_MODE, key, GCMParameterSpec(128, sealed, 0, 12)) }
            return c.doFinal(sealed, 12, sealed.size - 12)
        }
    }

    private class FailingBox : SecretBox {
        override fun seal(plain: ByteArray): ByteArray = throw IllegalStateException("no keystore")
        override fun open(sealed: ByteArray): ByteArray = throw IllegalStateException("no keystore")
    }

    private fun dir(): File = Files.createTempDirectory("lpc").toFile()
    private val legacyValue = "zephyr:abcdefghijkmnpqrstuvwxyz".take(31)

    @Test fun generatorFormat() {
        val rnd = SecureRandom()
        repeat(500) {
            val c = LocalProxyCredential.generate(rnd)
            assertTrue(c.startsWith("zephyr:"), c)
            val pw = LocalProxyCredential.password(c)
            assertEquals(24, pw.length)
            assertTrue(pw.all { it in LocalProxyCredential.ALPHABET }, c)
            assertTrue(pw.none { it in "0O1lI" }, c)
            assertTrue(LocalProxyCredential.isValid(c))
        }
        assertEquals(56, LocalProxyCredential.ALPHABET.length)
        assertEquals(LocalProxyCredential.ALPHABET.length, LocalProxyCredential.ALPHABET.toSet().size)
        assertFalse(LocalProxyCredential.isValid("zephyr:short"))
        assertFalse(LocalProxyCredential.isValid("admin:abcdefghijkmnpqrstuvwxy"))
        assertFalse(LocalProxyCredential.isValid("zephyr:0bcdefghijkmnpqrstuvwxy"))
        assertEquals("http://zephyr:pw@127.0.0.1:7890", LocalProxyCredential.url("http", "zephyr:pw", 7890))
        assertEquals("socks5://zephyr:pw@127.0.0.1:7890", LocalProxyCredential.url("socks5", "zephyr:pw", 7890))
    }

    @Test fun generatesOnceAndSealsAtRest() {
        val d = dir(); val box = TestBox()
        val first = LocalProxyCredentialStore(d, box).get()
        assertTrue(LocalProxyCredential.isValid(first))
        val sealed = File(d, LocalProxyCredentialStore.SEALED)
        assertTrue(sealed.isFile)
        assertFalse(String(sealed.readBytes(), Charsets.ISO_8859_1).contains(LocalProxyCredential.password(first)), "stored in plain text")
        assertFalse(File(d, LocalProxyCredentialStore.LEGACY).exists())
        assertEquals(first, LocalProxyCredentialStore(d, box).get()) // new process, same key → same credential
    }

    @Test fun migratesLegacyPlainTextThenDeletesIt() {
        val d = dir(); val box = TestBox()
        assertTrue(LocalProxyCredential.isValid(legacyValue))
        File(d, LocalProxyCredentialStore.LEGACY).writeText(legacyValue + "\n")
        assertEquals(legacyValue, LocalProxyCredentialStore(d, box) { error("must not generate") }.get())
        assertFalse(File(d, LocalProxyCredentialStore.LEGACY).exists(), "plain file left behind")
        assertTrue(File(d, LocalProxyCredentialStore.SEALED).isFile)
        assertEquals(legacyValue, LocalProxyCredentialStore(d, box) { error("must not generate") }.get())
    }

    @Test fun keepsLegacyFileWhenSealingFails() {
        val d = dir()
        File(d, LocalProxyCredentialStore.LEGACY).writeText(legacyValue)
        assertEquals(legacyValue, LocalProxyCredentialStore(d, FailingBox()).get())
        assertTrue(File(d, LocalProxyCredentialStore.LEGACY).isFile, "would lose the only copy")
        assertFalse(File(d, LocalProxyCredentialStore.SEALED).exists())
    }

    @Test fun neverWritesPlainTextWithoutKeystore() {
        val d = dir()
        val st = LocalProxyCredentialStore(d, FailingBox())
        val v = st.get()
        assertTrue(LocalProxyCredential.isValid(v))
        assertEquals(v, st.get())
        assertTrue(d.listFiles().orEmpty().isEmpty(), "nothing on disk: ${d.list()?.toList()}")
    }

    @Test fun invalidLegacyIsIgnoredAndRemovedAfterNewSealed() {
        val d = dir()
        File(d, LocalProxyCredentialStore.LEGACY).writeText("zephyr:")
        val v = LocalProxyCredentialStore(d, TestBox()).get()
        assertTrue(LocalProxyCredential.isValid(v))
        assertTrue(File(d, LocalProxyCredentialStore.SEALED).isFile)
    }

    @Test fun unreadableSealedFileFallsBackToLegacyOrNew() {
        val d = dir()
        LocalProxyCredentialStore(d, TestBox()).get()
        // Different key (e.g. data restored onto another device): the sealed copy no longer opens.
        File(d, LocalProxyCredentialStore.LEGACY).writeText(legacyValue)
        assertEquals(legacyValue, LocalProxyCredentialStore(d, TestBox()).get())
    }

    @Test fun resetAndRestore() {
        val d = dir(); val box = TestBox()
        val st = LocalProxyCredentialStore(d, box)
        val a = st.get()
        val b = st.reset()
        assertNotEquals(a, b)
        assertTrue(LocalProxyCredential.isValid(b))
        assertEquals(b, LocalProxyCredentialStore(d, box).get())
        st.restore(a)
        assertEquals(a, st.get())
        assertEquals(a, LocalProxyCredentialStore(d, box).get())
    }

    @Test fun mockCredential() = runTest {
        val m = MockEngine(scope = backgroundScope)
        assertEquals("zephyr:mockmockmockmockmockmock", m.localProxyCredential())
        assertEquals(24, LocalProxyCredential.password(m.localProxyCredential()).length)
        val r = m.resetLocalProxyCredential()
        assertTrue(LocalProxyCredential.isValid(r))
        assertEquals(r, m.localProxyCredential())
    }

    @Test fun portRange() {
        val d = Settings()
        assertFalse(CoreEngine.isValid(d.copy(localProxyPort = 1023)))
        assertTrue(CoreEngine.isValid(d.copy(localProxyPort = 1024)))
        assertTrue(CoreEngine.isValid(d.copy(localProxyPort = 65535)))
        assertFalse(CoreEngine.isValid(d.copy(localProxyPort = 65536)))
        assertEquals(d.localProxyPort, CoreEngine.sanitized(d.copy(localProxyPort = 80)).localProxyPort)
        assertTrue(CoreEngine.usesUserPort(d.copy(localProxyEnabled = true)))
        assertFalse(CoreEngine.usesUserPort(d.copy(localProxyEnabled = false)))
        // §16.f E12: private probe port always authenticates; the user's port follows 需要密码.
        val c = "zephyr:x"
        assertEquals(c, CoreEngine.proxyAuthFor(d.copy(localProxyEnabled = false, localProxyAuth = false), c))
        assertEquals(c, CoreEngine.proxyAuthFor(d.copy(localProxyEnabled = true, localProxyAuth = true), c))
        assertEquals(null, CoreEngine.proxyAuthFor(d.copy(localProxyEnabled = true, localProxyAuth = false), c))
    }
}
