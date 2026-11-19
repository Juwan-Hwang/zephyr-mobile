package com.zephyr.engine.core

import com.zephyr.core.mobile.MobileException
import com.zephyr.engine.ErrorCode
import com.zephyr.engine.ZephyrError
import com.zephyr.engine.ZephyrException

/**
 * Contract §16.b ①: the one authoritative `MobileError` → `ErrorCode` table. Call-site overrides are looked up
 * first, then the default column. [ErrorMappingTest] checks this row by row against the contract table.
 *
 * The engine `message` only goes to the log (and [ZephyrError.message]); the UI localises by code (§0.5, U27).
 */
object ErrorMapping {
    /** The core's error variants (`MobileError`), kept as a plain enum so the table is testable without JNA. */
    enum class Kind { IO, INVALID, CORRUPT, NOT_FOUND, RULE_INPUT_INVALID, SUBSCRIPTION_INVALID, STALE_TOKEN, SUBSCRIPTION_NOT_FOUND, SCENE_NOT_FOUND, NOT_RUNNING, CANCELLED }

    /** Calls the contract table names an override for; [OTHER] = every other call. */
    enum class Call {
        OTHER,
        PARSE_IMPORT_PAYLOAD, IMPORT_SUBSCRIPTION, PREVIEW_SUBSCRIPTION_UPDATE, UPDATE_SUBSCRIPTION,
        TEST_RULE, OVERRIDE_HOST, CONNECTION_TRACE, HOST_TRACE, SET_SCENE_NODE_FILTER,
        NODE, NODE_DETAIL, SCENE_CANDIDATES,
        GROUP_MEMBERS, SELECT_IN_GROUP, TEST_GROUP,
        /** Startup reads that rebuild once on `Corrupt` (nodeIndex / ruleStats); the platform retries, see [CoreEngine]. */
        NODE_INDEX, RULE_STATS,
    }

    /** `os error 28` / `No space left` / `ENOSPC` in an Io message → storage_full, for any call. */
    fun isNoSpace(message: String): Boolean =
        message.contains("os error 28", ignoreCase = true) || message.contains("No space left", ignoreCase = true) || message.contains("ENOSPC")

    /** Core's "节点库未建立" (store never built: no subscription yet). */
    fun isNoStore(message: String): Boolean = message.contains("节点库未建立")

    fun map(kind: Kind, message: String, call: Call = Call.OTHER): ErrorCode = when (kind) {
        Kind.IO -> if (isNoSpace(message)) ErrorCode.STORAGE_FULL else ErrorCode.INTERNAL
        Kind.INVALID -> when (call) {
            Call.PARSE_IMPORT_PAYLOAD, Call.IMPORT_SUBSCRIPTION, Call.PREVIEW_SUBSCRIPTION_UPDATE, Call.UPDATE_SUBSCRIPTION -> ErrorCode.SUBSCRIPTION_INVALID
            Call.TEST_RULE, Call.OVERRIDE_HOST, Call.CONNECTION_TRACE, Call.SET_SCENE_NODE_FILTER -> ErrorCode.RULE_INPUT_INVALID
            else -> ErrorCode.INTERNAL
        }
        // Startup nodeIndex / ruleStats rebuild once before this is reported (CoreEngine.rebuildOnCorrupt).
        Kind.CORRUPT -> ErrorCode.INTERNAL
        Kind.NOT_FOUND -> when {
            isNoStore(message) -> ErrorCode.SUBSCRIPTION_NOT_FOUND
            call == Call.NODE || call == Call.NODE_DETAIL || call == Call.SCENE_CANDIDATES -> ErrorCode.NODE_NOT_FOUND
            call == Call.GROUP_MEMBERS || call == Call.SELECT_IN_GROUP || call == Call.TEST_GROUP -> ErrorCode.GROUP_NOT_FOUND
            call == Call.HOST_TRACE || call == Call.CONNECTION_TRACE -> ErrorCode.NODE_NOT_FOUND
            else -> ErrorCode.INTERNAL
        }
        Kind.RULE_INPUT_INVALID -> ErrorCode.RULE_INPUT_INVALID
        Kind.SUBSCRIPTION_INVALID -> ErrorCode.SUBSCRIPTION_INVALID
        Kind.STALE_TOKEN -> ErrorCode.STALE_TOKEN
        Kind.SUBSCRIPTION_NOT_FOUND -> ErrorCode.SUBSCRIPTION_NOT_FOUND
        Kind.SCENE_NOT_FOUND -> ErrorCode.SCENE_NOT_FOUND
        Kind.NOT_RUNNING -> ErrorCode.NOT_RUNNING
        Kind.CANCELLED -> ErrorCode.CANCELLED
    }

    fun kind(e: MobileException): Kind = when (e) {
        is MobileException.Io -> Kind.IO
        is MobileException.Invalid -> Kind.INVALID
        is MobileException.Corrupt -> Kind.CORRUPT
        is MobileException.NotFound -> Kind.NOT_FOUND
        is MobileException.RuleInputInvalid -> Kind.RULE_INPUT_INVALID
        is MobileException.SubscriptionInvalid -> Kind.SUBSCRIPTION_INVALID
        is MobileException.StaleToken -> Kind.STALE_TOKEN
        is MobileException.SubscriptionNotFound -> Kind.SUBSCRIPTION_NOT_FOUND
        is MobileException.SceneNotFound -> Kind.SCENE_NOT_FOUND
        is MobileException.NotRunning -> Kind.NOT_RUNNING
        is MobileException.Cancelled -> Kind.CANCELLED
    }

    fun code(e: MobileException, call: Call = Call.OTHER): ErrorCode = map(kind(e), e.message ?: "", call)

    fun exception(e: MobileException, call: Call = Call.OTHER): ZephyrException =
        ZephyrException(ZephyrError(code(e, call), e.message ?: e.javaClass.simpleName))

    /** Platform I/O (writing the runtime config, settings): ENOSPC → storage_full, everything else internal (§16.b ①). */
    fun platformIo(t: Throwable): ZephyrException {
        val msg = generateSequence(t) { it.cause }.mapNotNull { it.message }.joinToString(" | ")
        return ZephyrException(if (isNoSpace(msg)) ErrorCode.STORAGE_FULL else ErrorCode.INTERNAL, msg.ifEmpty { t.javaClass.simpleName })
    }
}
