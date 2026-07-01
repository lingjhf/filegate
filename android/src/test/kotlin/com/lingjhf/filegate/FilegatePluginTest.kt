package com.lingjhf.filegate

import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.EventChannel
import java.io.ByteArrayInputStream
import java.io.File
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
    fun isTreeUri_returnsFalseForMediaProviderContentUri() {
        assertEquals(
            false,
            FilegatePlugin.isTreeUri("content://media/external/images/media/100")
        )
    }

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
    fun onMethodCall_writeWithMissingPath_returnsInvalidArgs() {
        val plugin = FilegatePlugin()

        val call = MethodCall("write", null)
        val mockResult: MethodChannel.Result = Mockito.mock(MethodChannel.Result::class.java)
        plugin.onMethodCall(call, mockResult)

        Mockito.verify(mockResult).error(
            "invalid_args",
            "A non-empty file path is required.",
            null
        )
    }

    @Test
    fun onMethodCall_writeWithMissingBytes_returnsInvalidArgs() {
        val plugin = FilegatePlugin()

        val call = MethodCall("write", mapOf("path" to "/tmp/filegate-test.txt"))
        val mockResult: MethodChannel.Result = Mockito.mock(MethodChannel.Result::class.java)
        plugin.onMethodCall(call, mockResult)

        Mockito.verify(mockResult).error(
            "invalid_args",
            "A byte payload is required.",
            null
        )
    }

    @Test
    fun onMethodCall_writeWithUnknownMode_returnsInvalidArgs() {
        val plugin = FilegatePlugin()

        val call = MethodCall(
            "write",
            mapOf(
                "path" to "/tmp/filegate-test.txt",
                "bytes" to byteArrayOf(1),
                "mode" to "unknown"
            )
        )
        val mockResult: MethodChannel.Result = Mockito.mock(MethodChannel.Result::class.java)
        plugin.onMethodCall(call, mockResult)

        Mockito.verify(mockResult).error(
            "invalid_args",
            "Unknown write mode: unknown.",
            null
        )
    }

    @Test
    fun onMethodCall_writeWithMissingFile_returnsPathNotFound() {
        val plugin = FilegatePlugin()
        val file = File.createTempFile("filegate-missing", ".txt")
        file.delete()

        val call = MethodCall(
            "write",
            mapOf(
                "path" to file.absolutePath,
                "bytes" to byteArrayOf(1),
                "mode" to "append"
            )
        )
        val mockResult: MethodChannel.Result = Mockito.mock(MethodChannel.Result::class.java)
        plugin.onMethodCall(call, mockResult)

        Mockito.verify(mockResult).error(
            "path_not_found",
            "The provided path does not exist.",
            file.absolutePath
        )
    }

    @Test
    fun onMethodCall_writeAppend_addsBytesAndReturnsEntry() {
        val plugin = FilegatePlugin()
        val file = File.createTempFile("filegate-write-append", ".txt")
        try {
            file.writeText("hello")
            val call = MethodCall(
                "write",
                mapOf(
                    "path" to file.absolutePath,
                    "bytes" to " world".toByteArray(),
                    "mode" to "append"
                )
            )
            val mockResult: MethodChannel.Result = Mockito.mock(MethodChannel.Result::class.java)

            plugin.onMethodCall(call, mockResult)

            assertEquals("hello world", file.readText())
            val captor = org.mockito.ArgumentCaptor.forClass(Any::class.java)
            Mockito.verify(mockResult).success(captor.capture())
            @Suppress("UNCHECKED_CAST")
            val entry = captor.value as Map<String, Any?>
            assertEquals(file.path, entry["path"])
            assertEquals("file", entry["kind"])
            @Suppress("UNCHECKED_CAST")
            val metadata = entry["metadata"] as Map<String, Any?>
            assertEquals(11L, metadata["size"])
        } finally {
            file.delete()
        }
    }

    @Test
    fun onMethodCall_writeReplace_truncatesFile() {
        val plugin = FilegatePlugin()
        val file = File.createTempFile("filegate-write-replace", ".txt")
        try {
            file.writeText("hello")
            val call = MethodCall(
                "write",
                mapOf(
                    "path" to file.absolutePath,
                    "bytes" to "ok".toByteArray(),
                    "mode" to "replace"
                )
            )
            val mockResult: MethodChannel.Result = Mockito.mock(MethodChannel.Result::class.java)

            plugin.onMethodCall(call, mockResult)

            assertEquals("ok", file.readText())
            Mockito.verify(mockResult).success(Mockito.any())
        } finally {
            file.delete()
        }
    }

    @Test
    fun onMethodCall_writeDirectory_returnsNotAFile() {
        val plugin = FilegatePlugin()

        val call = MethodCall(
            "write",
            mapOf(
                "path" to System.getProperty("java.io.tmpdir"),
                "bytes" to byteArrayOf(1),
                "mode" to "append"
            )
        )
        val mockResult: MethodChannel.Result = Mockito.mock(MethodChannel.Result::class.java)
        plugin.onMethodCall(call, mockResult)

        Mockito.verify(mockResult).error(
            "not_a_file",
            "The provided path is a directory, not a file.",
            System.getProperty("java.io.tmpdir")
        )
    }

    @Test
    fun onMethodCall_startWriteWithMissingPath_returnsInvalidArgs() {
        val plugin = FilegatePlugin()

        val call = MethodCall("startWrite", null)
        val mockResult: MethodChannel.Result = Mockito.mock(MethodChannel.Result::class.java)
        plugin.onMethodCall(call, mockResult)

        Mockito.verify(mockResult).error(
            "invalid_args",
            "A non-empty file path is required.",
            null
        )
    }

    @Test
    fun onMethodCall_writeChunkWithMissingSession_returnsNotFound() {
        val plugin = FilegatePlugin()

        val call = MethodCall(
            "writeChunk",
            mapOf(
                "sessionId" to "missing",
                "bytes" to byteArrayOf(1)
            )
        )
        val mockResult: MethodChannel.Result = Mockito.mock(MethodChannel.Result::class.java)
        plugin.onMethodCall(call, mockResult)

        Mockito.verify(mockResult).error(
            "write_session_not_found",
            "The write session was not found.",
            "missing"
        )
    }

    @Test
    fun onMethodCall_streamWriteAppend_addsChunksAndReturnsEntry() {
        val plugin = FilegatePlugin()
        val file = File.createTempFile("filegate-write-stream-append", ".txt")
        try {
            file.writeText("hello")
            val sessionId = startWrite(plugin, file, "append")

            plugin.onMethodCall(
                MethodCall(
                    "writeChunk",
                    mapOf(
                        "sessionId" to sessionId,
                        "bytes" to " ".toByteArray()
                    )
                ),
                Mockito.mock(MethodChannel.Result::class.java)
            )
            plugin.onMethodCall(
                MethodCall(
                    "writeChunk",
                    mapOf(
                        "sessionId" to sessionId,
                        "bytes" to "world".toByteArray()
                    )
                ),
                Mockito.mock(MethodChannel.Result::class.java)
            )

            val finishResult: MethodChannel.Result = Mockito.mock(MethodChannel.Result::class.java)
            plugin.onMethodCall(
                MethodCall("finishWrite", mapOf("sessionId" to sessionId)),
                finishResult
            )

            assertEquals("hello world", file.readText())
            val captor = org.mockito.ArgumentCaptor.forClass(Any::class.java)
            Mockito.verify(finishResult).success(captor.capture())
            @Suppress("UNCHECKED_CAST")
            val entry = captor.value as Map<String, Any?>
            @Suppress("UNCHECKED_CAST")
            val metadata = entry["metadata"] as Map<String, Any?>
            assertEquals(11L, metadata["size"])
        } finally {
            file.delete()
        }
    }

    @Test
    fun onMethodCall_streamWriteReplace_truncatesOnStart() {
        val plugin = FilegatePlugin()
        val file = File.createTempFile("filegate-write-stream-replace", ".txt")
        try {
            file.writeText("hello")
            val sessionId = startWrite(plugin, file, "replace")

            assertEquals("", file.readText())

            val finishResult: MethodChannel.Result = Mockito.mock(MethodChannel.Result::class.java)
            plugin.onMethodCall(
                MethodCall("finishWrite", mapOf("sessionId" to sessionId)),
                finishResult
            )
            Mockito.verify(finishResult).success(Mockito.any())
        } finally {
            file.delete()
        }
    }

    @Test
    fun onMethodCall_cancelWrite_isIdempotent() {
        val plugin = FilegatePlugin()
        val file = File.createTempFile("filegate-write-stream-cancel", ".txt")
        try {
            val sessionId = startWrite(plugin, file, "append")
            val call = MethodCall("cancelWrite", mapOf("sessionId" to sessionId))
            val firstResult: MethodChannel.Result = Mockito.mock(MethodChannel.Result::class.java)
            val secondResult: MethodChannel.Result = Mockito.mock(MethodChannel.Result::class.java)

            plugin.onMethodCall(call, firstResult)
            plugin.onMethodCall(call, secondResult)

            Mockito.verify(firstResult).success(null)
            Mockito.verify(secondResult).success(null)
        } finally {
            file.delete()
        }
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

    private fun startWrite(plugin: FilegatePlugin, file: File, mode: String): String {
        val call = MethodCall(
            "startWrite",
            mapOf(
                "path" to file.absolutePath,
                "mode" to mode
            )
        )
        val result: MethodChannel.Result = Mockito.mock(MethodChannel.Result::class.java)
        plugin.onMethodCall(call, result)
        val captor = org.mockito.ArgumentCaptor.forClass(Any::class.java)
        Mockito.verify(result).success(captor.capture())
        return captor.value as String
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
