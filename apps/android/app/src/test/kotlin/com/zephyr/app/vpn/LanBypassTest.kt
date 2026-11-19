package com.zephyr.app.vpn

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.math.BigInteger
import java.net.InetAddress

/** Contract §16.a① (E10): the API < 33 complement tables are exactly 0/0 minus the excluded LAN set. */
class LanBypassTest {
    private data class Range(val lo: BigInteger, val hi: BigInteger) // inclusive

    private fun bits(cidr: String) = if (cidr.contains(':')) 128 else 32

    private fun range(cidr: String): Range {
        val (a, len) = LanBypass.split(cidr)
        val w = bits(cidr)
        val base = BigInteger(1, InetAddress.getByName(a).address)
        val size = BigInteger.ONE.shiftLeft(w - len)
        assertEquals("$cidr: host bits must be zero (VpnService.Builder rejects them)", BigInteger.ZERO, base.mod(size))
        return Range(base, base + size - BigInteger.ONE)
    }

    /** Minimal CIDR cover of [all] minus [excluded], computed independently of the constant tables. */
    private fun complement(width: Int, excluded: List<String>): List<Range> {
        val ex = excluded.map(::range).sortedBy { it.lo }
        val out = mutableListOf<Range>()
        var cur = BigInteger.ZERO
        val max = BigInteger.ONE.shiftLeft(width) - BigInteger.ONE
        fun cover(from: BigInteger, to: BigInteger) {
            var x = from
            while (x <= to) {
                var size = BigInteger.ONE.shiftLeft(width)
                while (size > BigInteger.ONE && (x.mod(size) != BigInteger.ZERO || x + size - BigInteger.ONE > to)) size = size.shiftRight(1)
                out += Range(x, x + size - BigInteger.ONE)
                x += size
            }
        }
        for (e in ex) {
            if (e.lo > cur) cover(cur, e.lo - BigInteger.ONE)
            if (e.hi + BigInteger.ONE > cur) cur = e.hi + BigInteger.ONE
        }
        if (cur <= max) cover(cur, max)
        return out
    }

    private fun covers(table: List<String>, ip: String): Boolean {
        val v = BigInteger(1, InetAddress.getByName(ip).address)
        return table.map(::range).any { v >= it.lo && v <= it.hi }
    }

    @Test fun v4TableIsTheComplementOfTheLanSet() {
        assertEquals(complement(32, LanBypass.V4_EXCLUDED), LanBypass.V4_ROUTES.map(::range))
        assertEquals(72, LanBypass.V4_ROUTES.size)
    }

    @Test fun v6TableIsTheComplementOfTheLanSet() {
        assertEquals(complement(128, LanBypass.V6_EXCLUDED), LanBypass.V6_ROUTES.map(::range))
    }

    @Test fun excludedSetMatchesContract() {
        assertEquals(
            listOf("10.0.0.0/8", "127.0.0.0/8", "169.254.0.0/16", "172.16.0.0/12", "192.168.0.0/16", "224.0.0.0/4", "255.255.255.255/32"),
            LanBypass.V4_EXCLUDED,
        )
        assertEquals(listOf("fe80::/10", "fc00::/7", "ff00::/8"), LanBypass.V6_EXCLUDED)
    }

    @Test fun lanStaysOutFakeIpAndCgnatStayIn() {
        val v4 = LanBypass.V4_ROUTES
        listOf("192.168.1.1", "10.1.2.3", "172.16.0.1", "172.31.255.255", "169.254.1.1", "224.0.0.251", "239.255.255.250", "255.255.255.255", "127.0.0.1")
            .forEach { assertFalse("$it must bypass the tunnel", covers(v4, it)) }
        // fake-ip (198.18/16, incl. the tun's own DNS) and carrier NAT (100.64/10) must still enter the tun.
        listOf("198.18.0.1", "198.18.0.2", "198.19.255.1", "100.64.0.1", "100.127.255.254", "8.8.8.8", "172.32.0.1", "192.169.0.1", "255.255.255.254")
            .forEach { assertTrue("$it must enter the tunnel", covers(v4, it)) }
        val v6 = LanBypass.V6_ROUTES
        listOf("fe80::1", "fd00::1", "fc00::1", "ff02::fb").forEach { assertFalse("$it must bypass", covers(v6, it)) }
        listOf("2001:4860:4860::8888", "64:ff9b::1", "fec0::1").forEach { assertTrue("$it must enter", covers(v6, it)) }
    }
}
