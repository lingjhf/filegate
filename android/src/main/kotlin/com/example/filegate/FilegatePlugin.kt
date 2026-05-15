package com.example.filegate

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.DocumentsContract
import androidx.documentfile.provider.DocumentFile
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import io.flutter.plugin.common.PluginRegistry
import java.io.File
import java.io.FileNotFoundException
import java.io.FileInputStream
import java.io.InputStream
import java.util.UUID
import java.util.concurrent.Executors

class FilegatePlugin :
    FlutterPlugin,
    MethodCallHandler,
    ActivityAware,
    PluginRegistry.ActivityResultListener {
    private lateinit var applicationContext: Context
    private lateinit var messenger: io.flutter.plugin.common.BinaryMessenger
    private lateinit var channel: MethodChannel
    private var activity: Activity? = null
    private var activityBinding: ActivityPluginBinding? = null
    private val readChannels = mutableMapOf<String, EventChannel>()
    private val readHandlers = mutableMapOf<String, FileReadStreamHandler>()
    private var pendingPick: PendingPick? = null

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        applicationContext = flutterPluginBinding.applicationContext
        messenger = flutterPluginBinding.binaryMessenger
        channel = MethodChannel(flutterPluginBinding.binaryMessenger, "filegate")
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(
        call: MethodCall,
        result: Result
    ) {
        when (call.method) {
            "pick" -> pick(call.arguments as? Map<String, Any?>, result)
            "getFileSize" -> getFileSize(call.arguments as? Map<String, Any?>, result)
            "startRead" -> startRead(call.arguments as? Map<String, Any?>, result)
            "cancelRead" -> cancelRead(call.arguments as? Map<String, Any?>, result)
            else -> result.notImplemented()
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        pendingPick = null
        readHandlers.values.toList().forEach { it.cancel() }
        readHandlers.clear()
        readChannels.values.toList().forEach { it.setStreamHandler(null) }
        readChannels.clear()
        channel.setMethodCallHandler(null)
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
        activityBinding = binding
        binding.addActivityResultListener(this)
    }

    override fun onDetachedFromActivityForConfigChanges() {
        activityBinding?.removeActivityResultListener(this)
        activityBinding = null
        activity = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        onAttachedToActivity(binding)
    }

    override fun onDetachedFromActivity() {
        onDetachedFromActivityForConfigChanges()
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != requestCodePick) {
            return false
        }

        val pending = pendingPick ?: return false
        pendingPick = null

        if (resultCode != Activity.RESULT_OK || data == null) {
            pending.result.success(null)
            return true
        }

        try {
            val entries = when (pending.selectionMode) {
                "filesOnly" -> handlePickedFiles(data, pending.allowedExtensions)
                "directoriesOnly" -> handlePickedDirectory(data, pending.recursive, pending.allowedExtensions)
                "filesAndDirectories" -> throw FilegateError(
                    code = "unsupported_mode",
                    message = mixedModeUnsupportedMessage
                )
                else -> throw FilegateError(
                    code = "invalid_args",
                    message = "Unknown selection mode: ${pending.selectionMode}."
                )
            }
            pending.result.success(entries)
        } catch (error: FilegateError) {
            pending.result.error(error.code, error.message, error.details)
        } catch (error: SecurityException) {
            pending.result.error("permission_denied", error.localizedMessage, null)
        } catch (error: Exception) {
            pending.result.error("enumeration_failed", error.localizedMessage, null)
        }

        return true
    }

    private fun pick(arguments: Map<String, Any?>?, result: Result) {
        val currentActivity = activity
            ?: run {
                result.error("no_activity", "File chooser requires a foreground activity.", null)
                return
            }

        if (pendingPick != null) {
            result.error("picker_active", "Another file picker request is already active.", null)
            return
        }

        val selectionMode = arguments?.get("selectionMode") as? String ?: "filesOnly"
        if (selectionMode == "filesAndDirectories") {
            result.error(
                "unsupported_mode",
                mixedModeUnsupportedMessage,
                null
            )
            return
        }

        val allowMultiple = arguments?.get("allowMultiple") as? Boolean ?: false
        val recursive = arguments?.get("recursive") as? Boolean ?: false
        val allowedExtensions = (arguments?.get("allowedExtensions") as? List<*>)
            ?.mapNotNull { it as? String }
            ?: emptyList()
        val initialDirectory = arguments?.get("initialDirectory") as? String

        val intent = when (selectionMode) {
            "filesOnly" -> buildOpenDocumentIntent(allowMultiple, initialDirectory)
            "directoriesOnly" -> buildOpenDocumentTreeIntent(initialDirectory)
            else -> {
                result.error("invalid_args", "Unknown selection mode: $selectionMode.", null)
                return
            }
        }

        pendingPick = PendingPick(result, selectionMode, recursive, allowedExtensions)
        currentActivity.startActivityForResult(intent, requestCodePick)
    }

    private fun startRead(arguments: Map<String, Any?>?, result: Result) {
        val path = arguments?.get("path") as? String
        if (path.isNullOrEmpty()) {
            result.error("invalid_args", "A non-empty file path is required.", null)
            return
        }

        val chunkSize = when (val rawChunkSize = arguments?.get("chunkSize")) {
            is Int -> rawChunkSize
            is Long -> rawChunkSize.toInt()
            else -> 64 * 1024
        }
        val start = when (val rawStart = arguments?.get("start")) {
            is Int -> rawStart.toLong()
            is Long -> rawStart
            else -> 0L
        }

        if (chunkSize <= 0) {
            result.error("invalid_args", "chunkSize must be greater than zero.", null)
            return
        }
        if (start < 0) {
            result.error("invalid_args", "start must not be negative.", null)
            return
        }

        try {
            if (isDirectory(path)) {
                result.error("not_a_file", "The provided path is a directory, not a file.", path)
                return
            }

            val streamId = UUID.randomUUID().toString()
            val eventChannel = EventChannel(messenger, "$readChannelPrefix/$streamId")
            val handler = FileReadStreamHandler(
                openStream = { openInputStream(path, start) },
                chunkSize = chunkSize,
                onDispose = { releaseReadStream(streamId) }
            )
            eventChannel.setStreamHandler(handler)
            readChannels[streamId] = eventChannel
            readHandlers[streamId] = handler
            result.success(streamId)
        } catch (error: FilegateError) {
            result.error(error.code, error.message, error.details)
        } catch (error: SecurityException) {
            result.error("permission_denied", error.localizedMessage, path)
        } catch (error: Exception) {
            result.error("read_failed", error.localizedMessage, path)
        }
    }

    private fun getFileSize(arguments: Map<String, Any?>?, result: Result) {
        val path = arguments?.get("path") as? String
        if (path.isNullOrEmpty()) {
            result.error("invalid_args", "A non-empty file path is required.", null)
            return
        }

        try {
            if (isDirectory(path)) {
                result.error("not_a_file", "The provided path is a directory, not a file.", path)
                return
            }

            result.success(resolveFileSize(path))
        } catch (error: FilegateError) {
            result.error(error.code, error.message, error.details)
        } catch (error: SecurityException) {
            result.error("permission_denied", error.localizedMessage, path)
        } catch (error: Exception) {
            result.error("read_failed", error.localizedMessage, path)
        }
    }

    private fun cancelRead(arguments: Map<String, Any?>?, result: Result) {
        val streamId = arguments?.get("streamId") as? String
        if (streamId.isNullOrEmpty()) {
            result.error("invalid_args", "A non-empty streamId is required.", null)
            return
        }

        releaseReadStream(streamId)
        result.success(null)
    }

    private fun releaseReadStream(streamId: String) {
        readHandlers.remove(streamId)?.cancel()
        readChannels.remove(streamId)?.setStreamHandler(null)
    }

    private fun buildOpenDocumentIntent(
        allowMultiple: Boolean,
        initialDirectory: String?
    ): Intent {
        return Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "*/*"
            putExtra(Intent.EXTRA_ALLOW_MULTIPLE, allowMultiple)
            maybePutInitialUri(initialDirectory)
        }
    }

    private fun buildOpenDocumentTreeIntent(initialDirectory: String?): Intent {
        return Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
            maybePutInitialUri(initialDirectory)
        }
    }

    private fun Intent.maybePutInitialUri(initialDirectory: String?) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O || initialDirectory.isNullOrEmpty()) {
            return
        }

        runCatching { Uri.parse(initialDirectory) }
            .getOrNull()
            ?.let { putExtra(DocumentsContract.EXTRA_INITIAL_URI, it) }
    }

    private fun handlePickedFiles(
        data: Intent,
        allowedExtensions: List<String>
    ): List<Map<String, Any?>> {
        val uris = mutableListOf<Uri>()
        val clipData = data.clipData
        if (clipData != null) {
            for (index in 0 until clipData.itemCount) {
                clipData.getItemAt(index).uri?.let(uris::add)
            }
        } else {
            data.data?.let(uris::add)
        }

        return uris.mapNotNull { uri ->
            takePersistablePermission(data, uri)
            val document = DocumentFile.fromSingleUri(applicationContext, uri)
            val name = document?.name ?: queryDisplayName(uri) ?: uri.lastPathSegment ?: uri.toString()
            if (!matchesAllowedExtensions(name, allowedExtensions)) {
                null
            } else {
                serializeFileEntry(uri, name)
            }
        }
    }

    private fun handlePickedDirectory(
        data: Intent,
        recursive: Boolean,
        allowedExtensions: List<String>
    ): List<Map<String, Any?>> {
        val treeUri = data.data
            ?: throw FilegateError("path_not_found", "No directory URI was returned from the picker.")

        takePersistablePermission(data, treeUri)
        val root = DocumentFile.fromTreeUri(applicationContext, treeUri)
            ?: throw FilegateError("path_not_found", "Unable to resolve the selected directory.", treeUri.toString())

        if (!root.isDirectory) {
            throw FilegateError("not_a_directory", "The selected item is not a directory.", treeUri.toString())
        }

        val entries = mutableListOf<Map<String, Any?>>()
        val rootName = root.name ?: queryDisplayName(treeUri) ?: treeUri.lastPathSegment ?: treeUri.toString()
        collectFilesFromDirectory(root, recursive, allowedExtensions, entries, rootName)
        return entries
    }

    private fun collectFilesFromDirectory(
        directory: DocumentFile,
        recursive: Boolean,
        allowedExtensions: List<String>,
        destination: MutableList<Map<String, Any?>>, 
        currentRelativePath: String
    ) {
        for (child in directory.listFiles()) {
            when {
                child.isDirectory && recursive -> {
                    val childName = child.name ?: child.uri.lastPathSegment ?: child.uri.toString()
                    collectFilesFromDirectory(
                        child,
                        true,
                        allowedExtensions,
                        destination,
                        "$currentRelativePath/$childName"
                    )
                }
                child.isFile -> {
                    val name = child.name ?: child.uri.lastPathSegment ?: child.uri.toString()
                    if (matchesAllowedExtensions(name, allowedExtensions)) {
                        destination += serializeFileEntry(child.uri, name, "$currentRelativePath/$name")
                    }
                }
            }
        }
    }

    private fun serializeFileEntry(uri: Uri, name: String, relativePath: String = name): Map<String, Any?> {
        return mapOf(
            "path" to uri.toString(),
            "name" to name,
            "kind" to "file",
            "relativePath" to relativePath
        )
    }

    private fun takePersistablePermission(intent: Intent, uri: Uri) {
        val flags = intent.flags and
            (Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
        if (flags == 0) {
            return
        }

        runCatching {
            applicationContext.contentResolver.takePersistableUriPermission(uri, flags)
        }.onFailure { error ->
            if (error is SecurityException) {
                throw FilegateError(
                    "persist_permission_failed",
                    error.localizedMessage ?: "Unable to persist URI permission.",
                    uri.toString()
                )
            }
        }
    }

    private fun matchesAllowedExtensions(name: String, allowedExtensions: List<String>): Boolean {
        if (allowedExtensions.isEmpty()) {
            return true
        }

        val extension = name.substringAfterLast('.', missingDelimiterValue = "").lowercase()
        return allowedExtensions.any { it.lowercase() == extension }
    }

    private fun queryDisplayName(uri: Uri): String? {
        val projection = arrayOf(android.provider.OpenableColumns.DISPLAY_NAME)
        applicationContext.contentResolver.query(uri, projection, null, null, null)?.use { cursor ->
            val index = cursor.getColumnIndex(android.provider.OpenableColumns.DISPLAY_NAME)
            if (index >= 0 && cursor.moveToFirst()) {
                return cursor.getString(index)
            }
        }
        return null
    }

    private fun isDirectory(identifier: String): Boolean {
        val uri = Uri.parse(identifier)
        return when (uri.scheme) {
            "content" -> {
                if (DocumentsContract.isTreeUri(uri)) {
                    true
                } else {
                    DocumentFile.fromSingleUri(applicationContext, uri)?.isDirectory == true ||
                        DocumentFile.fromTreeUri(applicationContext, uri)?.isDirectory == true
                }
            }
            "file" -> File(uri.path.orEmpty()).isDirectory
            else -> File(identifier).isDirectory
        }
    }

    private fun openInputStream(
        identifier: String,
        start: Long
    ): InputStream {
        val uri = Uri.parse(identifier)
        val inputStream = when (uri.scheme) {
            "content" -> applicationContext.contentResolver.openInputStream(uri)
                ?: throw FilegateError("read_open_failed", "Unable to open the provided content URI.", identifier)
            "file" -> {
                val path = uri.path
                    ?: throw FilegateError("path_not_found", "The provided file URI has no path.", identifier)
                val file = File(path)
                if (!file.exists()) {
                    throw FilegateError("path_not_found", "The provided path does not exist.", identifier)
                }
                FileInputStream(file)
            }
            else -> {
                val file = File(identifier)
                if (!file.exists()) {
                    throw FilegateError("path_not_found", "The provided path does not exist.", identifier)
                }
                FileInputStream(file)
            }
        }

        skipFully(inputStream, start, identifier)
        return inputStream
    }

    private fun skipFully(
        inputStream: InputStream,
        start: Long,
        identifier: String
    ) {
        var remaining = start
        while (remaining > 0) {
            val skipped = inputStream.skip(remaining)
            if (skipped > 0) {
                remaining -= skipped
                continue
            }

            val probe = inputStream.read()
            if (probe == -1) {
                return
            }
            remaining -= 1
        }
    }

    private fun resolveFileSize(identifier: String): Long? {
        val uri = Uri.parse(identifier)
        return when (uri.scheme) {
            "content" -> resolveContentFileSize(uri, identifier)
            "file" -> {
                val path = uri.path
                    ?: throw FilegateError("path_not_found", "The provided file URI has no path.", identifier)
                val file = File(path)
                if (!file.exists()) {
                    throw FilegateError("path_not_found", "The provided path does not exist.", identifier)
                }
                file.length()
            }
            else -> {
                val file = File(identifier)
                if (!file.exists()) {
                    throw FilegateError("path_not_found", "The provided path does not exist.", identifier)
                }
                file.length()
            }
        }
    }

    private fun resolveContentFileSize(
        uri: Uri,
        identifier: String
    ): Long? {
        queryContentSize(uri)?.let { return it }

        val document = DocumentFile.fromSingleUri(applicationContext, uri)
        if (document == null) {
            try {
                applicationContext.contentResolver.openInputStream(uri)?.use { return null }
            } catch (_: FileNotFoundException) {
                throw FilegateError(
                    "path_not_found",
                    "The provided content URI does not exist.",
                    identifier
                )
            }

            throw FilegateError(
                "path_not_found",
                "The provided content URI does not exist.",
                identifier
            )
        }

        if (document.isDirectory) {
            throw FilegateError(
                "not_a_file",
                "The provided path is a directory, not a file.",
                identifier
            )
        }

        val length = document.length()
        return if (length >= 0) length else null
    }

    private fun queryContentSize(uri: Uri): Long? {
        val projection = arrayOf(android.provider.OpenableColumns.SIZE)
        applicationContext.contentResolver.query(uri, projection, null, null, null)?.use { cursor ->
            val index = cursor.getColumnIndex(android.provider.OpenableColumns.SIZE)
            if (index >= 0 && cursor.moveToFirst() && !cursor.isNull(index)) {
                return cursor.getLong(index)
            }
        }
        return null
    }

    private data class PendingPick(
        val result: Result,
        val selectionMode: String,
        val recursive: Boolean,
        val allowedExtensions: List<String>
    )

    private data class FilegateError(
        val code: String,
        override val message: String,
        val details: Any? = null
    ) : Exception(message)

    private class FileReadStreamHandler(
        private val openStream: () -> InputStream,
        private val chunkSize: Int,
        private val onDispose: () -> Unit
    ) : EventChannel.StreamHandler {
        private val executor = Executors.newSingleThreadExecutor()
        @Volatile private var isCancelled = false
        @Volatile private var eventSink: EventChannel.EventSink? = null
        @Volatile private var inputStream: InputStream? = null

        override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
            synchronized(this) {
                if (eventSink != null) {
                    events.error("stream_active", "This file stream is already active.", null)
                    return
                }

                try {
                    inputStream = openStream()
                } catch (error: FilegateError) {
                    events.error(error.code, error.message, error.details)
                    return
                } catch (error: SecurityException) {
                    events.error("permission_denied", error.localizedMessage, null)
                    return
                } catch (error: Exception) {
                    events.error("read_open_failed", error.localizedMessage, null)
                    return
                }

                isCancelled = false
                eventSink = events
            }

            executor.execute {
                readLoop()
            }
        }

        override fun onCancel(arguments: Any?) {
            cancel()
        }

        fun cancel() {
            isCancelled = true
            runCatching { inputStream?.close() }
            inputStream = null
            eventSink = null
            dispose()
        }

        private fun readLoop() {
            val stream = inputStream ?: run {
                dispose()
                return
            }

            try {
                val buffer = ByteArray(chunkSize)
                while (!isCancelled) {
                    val read = stream.read(buffer)
                    when {
                        read < 0 -> {
                            eventSink?.endOfStream()
                            return
                        }
                        read == 0 -> continue
                        else -> eventSink?.success(buffer.copyOf(read))
                    }
                }
            } catch (error: Exception) {
                if (!isCancelled) {
                    eventSink?.error("read_failed", error.localizedMessage, null)
                }
            } finally {
                runCatching { stream.close() }
                inputStream = null
                eventSink = null
                executor.shutdown()
                dispose()
            }
        }

        private fun dispose() {
            onDispose()
        }
    }

    companion object {
        private const val requestCodePick = 64321
        private const val readChannelPrefix = "filegate/read"
        private const val mixedModeUnsupportedMessage =
            "Android Storage Access Framework does not provide a single system picker intent for mixed file and directory selection. Use ACTION_OPEN_DOCUMENT for files or ACTION_OPEN_DOCUMENT_TREE for directories."
    }
}
