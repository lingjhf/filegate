package com.lingjhf.filegate

import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.EventChannel
import java.io.ByteArrayInputStream
import java.io.IOException
import java.io.InputStream
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import org.mockito.Mockito
import kotlin.test.assertEquals
import kotlin.test.assertTrue
import kotlin.test.Test

internal class FilegatePluginTest {
    @Test
    fun onMethodCall_getFileSizeWithMissingPath_returnsInvalidArgs() {
        val plugin = FilegatePlugin()

        val call = MethodCall("getFileSize", null)
        val mockResult: MethodChannel.Result = Mockito.mock(MethodChannel.Result::class.java)
        plugin.onMethodCall(call, mockResult)

        Mockito.verify(mockResult).error(
            "invalid_args",
            "A non-empty file path is required.",
            null
        )
    }

    @Test
    fun onMethodCall_saveWithoutActivity_returnsNoActivity() {
        val plugin = FilegatePlugin()

        val call = MethodCall(
            "save",
            mapOf(
                "bytes" to byteArrayOf(1, 2, 3),
                "suggestedName" to "export.txt"
            )
        )
        val mockResult: MethodChannel.Result = Mockito.mock(MethodChannel.Result::class.java)
        plugin.onMethodCall(call, mockResult)

        Mockito.verify(mockResult).error(
            "no_activity",
            "File saver requires a foreground activity.",
            null
        )
    }

    @Test
    fun fileReadStreamHandler_keepsChannelUntilFlutterCancelsAfterEnd() {
        var disposeCount = 0
        val handler = FilegatePlugin.FileReadStreamHandler(
            openStream = { ByteArrayInputStream(byteArrayOf(1, 2, 3)) },
            chunkSize = 2,
            maxBytes = null,
            dispatchEvent = { action -> action() },
            onDispose = { disposeCount += 1 }
        )
        val sink = RecordingEventSink()

        handler.onListen(null, sink)

        assertTrue(sink.awaitEnd())
        assertEquals(listOf(listOf(1, 2), listOf(3)), sink.successEvents)
        assertEquals(0, disposeCount)

        handler.onCancel(null)

        assertEquals(1, disposeCount)
    }

    @Test
    fun fileReadStreamHandler_keepsChannelUntilFlutterCancelsAfterOpenFailure() {
        var disposeCount = 0
        val handler = FilegatePlugin.FileReadStreamHandler(
            openStream = { throw IllegalStateException("boom") },
            chunkSize = 2,
            maxBytes = null,
            dispatchEvent = { action -> action() },
            onDispose = { disposeCount += 1 }
        )
        val sink = RecordingEventSink()

        handler.onListen(null, sink)

        assertTrue(sink.awaitEnd())
        assertEquals(listOf(RecordedError("read_open_failed", "boom", null)), sink.errorEvents)
        assertEquals(0, disposeCount)

        handler.onCancel(null)

        assertEquals(1, disposeCount)
    }

    @Test
    fun fileReadStreamHandler_reportsPermissionDeniedOpenFailure() {
        var disposeCount = 0
        val handler = FilegatePlugin.FileReadStreamHandler(
            openStream = { throw SecurityException("denied") },
            chunkSize = 2,
            maxBytes = null,
            dispatchEvent = { action -> action() },
            onDispose = { disposeCount += 1 }
        )
        val sink = RecordingEventSink()

        handler.onListen(null, sink)

        assertTrue(sink.awaitEnd())
        assertEquals(listOf(RecordedError("permission_denied", "denied", null)), sink.errorEvents)
        assertEquals(0, disposeCount)

        handler.onCancel(null)

        assertEquals(1, disposeCount)
    }

    @Test
    fun fileReadStreamHandler_reportsReadFailuresAndWaitsForCancel() {
        var disposeCount = 0
        val handler = FilegatePlugin.FileReadStreamHandler(
            openStream = {
                object : InputStream() {
                    override fun read(): Int {
                        throw IOException("boom")
                    }
                }
            },
            chunkSize = 2,
            maxBytes = null,
            dispatchEvent = { action -> action() },
            onDispose = { disposeCount += 1 }
        )
        val sink = RecordingEventSink()

        handler.onListen(null, sink)

        assertTrue(sink.awaitEnd())
        assertEquals(listOf(RecordedError("read_failed", "boom", null)), sink.errorEvents)
        assertEquals(0, disposeCount)

        handler.onCancel(null)

        assertEquals(1, disposeCount)
    }

    @Test
    fun fileReadStreamHandler_stopsAtConfiguredByteLimit() {
        val handler = FilegatePlugin.FileReadStreamHandler(
            openStream = { ByteArrayInputStream(byteArrayOf(1, 2, 3, 4, 5)) },
            chunkSize = 3,
            maxBytes = 4,
            dispatchEvent = { action -> action() },
            onDispose = { }
        )
        val sink = RecordingEventSink()

        handler.onListen(null, sink)

        assertTrue(sink.awaitEnd())
        assertEquals(listOf(listOf(1, 2, 3), listOf(4)), sink.successEvents)
    }

    private class RecordingEventSink : EventChannel.EventSink {
        private val endLatch = CountDownLatch(1)
        val successEvents = mutableListOf<List<Int>>()
        val errorEvents = mutableListOf<RecordedError>()

        override fun success(event: Any?) {
            successEvents += (event as ByteArray).map { it.toInt() }
        }

        override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {
            errorEvents += RecordedError(errorCode, errorMessage, errorDetails)
        }

        override fun endOfStream() {
            endLatch.countDown()
        }

        fun awaitEnd(): Boolean = endLatch.await(1, TimeUnit.SECONDS)
    }

    private data class RecordedError(
        val code: String,
        val message: String?,
        val details: Any?
    )
}
