package com.zephyr.engine.core

import com.zephyr.core.mobile.MobileException
import com.zephyr.engine.ErrorCode
import com.zephyr.engine.core.ErrorMapping.Call
import com.zephyr.engine.core.ErrorMapping.Kind
import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * Contract §16.b ① table, row by row: (MobileError, message, call) → ErrorCode. Each row of the contract table has
 * its default case first, then every call-site override it names.
 */
class ErrorMappingTest {
    private data class Row(val kind: Kind, val message: String, val call: Call, val expected: ErrorCode)

    private val table = listOf(
        // Io: internal; os error 28 / No space left / ENOSPC → storage_full (any call)
        Row(Kind.IO, "permission denied", Call.OTHER, ErrorCode.INTERNAL),
        Row(Kind.IO, "No space left on device (os error 28)", Call.OTHER, ErrorCode.STORAGE_FULL),
        Row(Kind.IO, "write failed: os error 28", Call.IMPORT_SUBSCRIPTION, ErrorCode.STORAGE_FULL),
        Row(Kind.IO, "No space left", Call.UPDATE_SUBSCRIPTION, ErrorCode.STORAGE_FULL),
        Row(Kind.IO, "ENOSPC", Call.NODE_INDEX, ErrorCode.STORAGE_FULL),
        // Invalid: internal; subscription calls → subscription_invalid; host inputs / uhd filter → rule_input_invalid
        Row(Kind.INVALID, "x", Call.OTHER, ErrorCode.INTERNAL),
        Row(Kind.INVALID, "x", Call.PARSE_IMPORT_PAYLOAD, ErrorCode.SUBSCRIPTION_INVALID),
        Row(Kind.INVALID, "x", Call.IMPORT_SUBSCRIPTION, ErrorCode.SUBSCRIPTION_INVALID),
        Row(Kind.INVALID, "x", Call.PREVIEW_SUBSCRIPTION_UPDATE, ErrorCode.SUBSCRIPTION_INVALID),
        Row(Kind.INVALID, "x", Call.UPDATE_SUBSCRIPTION, ErrorCode.SUBSCRIPTION_INVALID),
        Row(Kind.INVALID, "x", Call.TEST_RULE, ErrorCode.RULE_INPUT_INVALID),
        Row(Kind.INVALID, "x", Call.OVERRIDE_HOST, ErrorCode.RULE_INPUT_INVALID),
        Row(Kind.INVALID, "x", Call.CONNECTION_TRACE, ErrorCode.RULE_INPUT_INVALID),
        Row(Kind.INVALID, "x", Call.SET_SCENE_NODE_FILTER, ErrorCode.RULE_INPUT_INVALID),
        // Corrupt: internal (startup nodeIndex / ruleStats rebuild once first, then internal)
        Row(Kind.CORRUPT, "节点文件截断", Call.OTHER, ErrorCode.INTERNAL),
        Row(Kind.CORRUPT, "节点文件截断", Call.NODE_INDEX, ErrorCode.INTERNAL),
        Row(Kind.CORRUPT, "规则文件截断", Call.RULE_STATS, ErrorCode.INTERNAL),
        // NotFound: internal; node calls → node_not_found; group calls → group_not_found; traces → node_not_found;
        // 节点库未建立 → subscription_not_found
        Row(Kind.NOT_FOUND, "rule provider x", Call.OTHER, ErrorCode.INTERNAL),
        Row(Kind.NOT_FOUND, "node 1f", Call.NODE, ErrorCode.NODE_NOT_FOUND),
        Row(Kind.NOT_FOUND, "node 1f", Call.NODE_DETAIL, ErrorCode.NODE_NOT_FOUND),
        Row(Kind.NOT_FOUND, "node 1f", Call.SCENE_CANDIDATES, ErrorCode.NODE_NOT_FOUND),
        Row(Kind.NOT_FOUND, "group x", Call.GROUP_MEMBERS, ErrorCode.GROUP_NOT_FOUND),
        Row(Kind.NOT_FOUND, "group x", Call.SELECT_IN_GROUP, ErrorCode.GROUP_NOT_FOUND),
        Row(Kind.NOT_FOUND, "group x", Call.TEST_GROUP, ErrorCode.GROUP_NOT_FOUND),
        Row(Kind.NOT_FOUND, "host a.com", Call.HOST_TRACE, ErrorCode.NODE_NOT_FOUND),
        Row(Kind.NOT_FOUND, "host a.com", Call.CONNECTION_TRACE, ErrorCode.NODE_NOT_FOUND),
        Row(Kind.NOT_FOUND, "v1=节点库未建立", Call.OTHER, ErrorCode.SUBSCRIPTION_NOT_FOUND),
        Row(Kind.NOT_FOUND, "v1=节点库未建立", Call.NODE_INDEX, ErrorCode.SUBSCRIPTION_NOT_FOUND),
        // One code each, no overrides
        Row(Kind.RULE_INPUT_INVALID, "x", Call.OTHER, ErrorCode.RULE_INPUT_INVALID),
        Row(Kind.SUBSCRIPTION_INVALID, "x", Call.OTHER, ErrorCode.SUBSCRIPTION_INVALID),
        Row(Kind.STALE_TOKEN, "x", Call.OTHER, ErrorCode.STALE_TOKEN),
        Row(Kind.SUBSCRIPTION_NOT_FOUND, "x", Call.OTHER, ErrorCode.SUBSCRIPTION_NOT_FOUND),
        Row(Kind.SCENE_NOT_FOUND, "x", Call.OTHER, ErrorCode.SCENE_NOT_FOUND),
        Row(Kind.SCENE_NOT_FOUND, "x", Call.SET_SCENE_NODE_FILTER, ErrorCode.SCENE_NOT_FOUND),
        Row(Kind.NOT_RUNNING, "x", Call.OTHER, ErrorCode.NOT_RUNNING),
        Row(Kind.CANCELLED, "x", Call.OTHER, ErrorCode.CANCELLED),
    )

    @Test fun contractTableRowByRow() {
        for (r in table) assertEquals(r.toString(), r.expected, ErrorMapping.map(r.kind, r.message, r.call))
    }

    @Test fun everyKindHasARow() {
        assertEquals(Kind.entries.toSet(), table.map { it.kind }.toSet())
    }

    @Test fun mapsGeneratedExceptions() {
        assertEquals(ErrorCode.STORAGE_FULL, ErrorMapping.code(MobileException.Io("No space left on device (os error 28)")))
        assertEquals(ErrorCode.SUBSCRIPTION_INVALID, ErrorMapping.code(MobileException.Invalid("bad"), Call.IMPORT_SUBSCRIPTION))
        assertEquals(ErrorCode.SUBSCRIPTION_NOT_FOUND, ErrorMapping.code(MobileException.NotFound("节点库未建立")))
        assertEquals(ErrorCode.GROUP_NOT_FOUND, ErrorMapping.code(MobileException.NotFound("group x"), Call.SELECT_IN_GROUP))
        assertEquals(ErrorCode.CANCELLED, ErrorMapping.code(MobileException.Cancelled()))
    }

    @Test fun platformIoNoSpaceIsStorageFull() {
        assertEquals(ErrorCode.STORAGE_FULL, ErrorMapping.platformIo(java.io.IOException("write failed: ENOSPC (No space left on device)")).code)
        assertEquals(ErrorCode.INTERNAL, ErrorMapping.platformIo(java.io.IOException("EACCES")).code)
    }
}
