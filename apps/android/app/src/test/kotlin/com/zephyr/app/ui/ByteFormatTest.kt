package com.zephyr.app.ui

import com.zephyr.design.format.ZFormat
import org.junit.Assert.assertEquals
import org.junit.Test

/** Contract §16.e ① (U21): decimal units, half-up, rollover; every sample from the contract plus the edges. */
class ByteFormatTest {
    private fun b(n: Long) = ZFormat.bytesText(n)
    private fun r(n: Long) = ZFormat.rateText(n)

    @Test fun contractSamples() {
        assertEquals("0 B", b(0))
        assertEquals("999 B", b(999))
        assertEquals("1 KB", b(1499))
        assertEquals("2 KB", b(1500))
        assertEquals("12.3 MB", b(12_345_678))
        assertEquals("186.4 GB", b(186_449_999_999))
        assertEquals("195 KB/s", r(194_600))
        assertEquals("2.8 MB/s", r(2_849_999))
    }

    @Test fun rolloverAfterRounding() {
        assertEquals("1.0 MB", b(999_600)) // 999.6 KB
        assertEquals("1.0 MB/s", r(999_960)) // 999.96 KB/s
        assertEquals("1.0 GB", b(999_999_999))
        assertEquals("1.0 TB", b(999_960_000_000))
        assertEquals("999 KB", b(999_499))
    }

    @Test fun megabytesAndUp() {
        assertEquals("99.9 MB", b(99_949_999))
        assertEquals("100 MB", b(99_950_000))
        assertEquals("123 MB", b(123_456_789))
        assertEquals("1.0 GB", b(1_000_000_000))
        assertEquals("1.5 TB", b(1_450_000_000_000))
        assertEquals("123.5 MB/s", r(123_456_789))
        assertEquals("999 B/s", r(999))
        assertEquals("1 KB/s", r(1_000))
    }

    @Test fun pairsForStatTiles() {
        assertEquals("2.8" to "MB", ZFormat.rate(2_800_000))
        assertEquals("195" to "KB", ZFormat.rate(195_000))
    }
}
