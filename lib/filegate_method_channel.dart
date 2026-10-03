import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'filegate_platform_interface.dart';
import 'src/errors.dart';
import 'src/file_read_session.dart';
import 'src/file_write_session.dart';
import 'src/models.dart';
import 'src/read_arguments.dart';

/// An implementation of [FilegatePlatform] that uses method channels.
class MethodChannelFilegate extends FilegatePlatform {
  MethodChannelFilegate({
    @visibleForTesting this.forceNativeRead = false,
    @visibleForTesting String? operatingSystem,
  }) : _operatingSystem = operatingSystem ?? Platform.operatingSystem;

  static const _readChannelPrefix = 'filegate/read';
  final bool forceNativeRead;
  final String _operatingSystem;

  @visibleForTesting
  final methodChannel = const MethodChannel('filegate');

  @override
  Future<FilegateCapabilities> getCapabilities() async {
    return capabilitiesForOperatingSystem(_operatingSystem);
  }

  @visibleForTesting
  static FilegateCapabilities capabilitiesForOperatingSystem(
    String operatingSystem,
  ) {
    return switch (operatingSystem) {
      'android' => const FilegateCapabilities(
        supportsFilePicking: true,
        supportsDirectoryPicking: true,
        supportsMixedPicking: false,
        supportsInitialDirectory: true,
        supportsPersistedAccess: true,
        supportsNativeUriRead: true,
        supportsFileSaving: true,
        supportsFileWriting: true,
        supportsFileStreamWriting: true,
        supportsMediaPicking: true,
        supportsGallerySaving: true,
      ),
      'ios' => const FilegateCapabilities(
        supportsFilePicking: true,
        supportsDirectoryPicking: true,
        supportsMixedPicking: true,
        supportsInitialDirectory: true,
        supportsPersistedAccess: false,
        supportsNativeUriRead: true,
        supportsFileSaving: true,
        supportsFileWriting: true,
        supportsFileStreamWriting: true,
        supportsMediaPicking: true,
        supportsGallerySaving: true,
      ),
      'macos' => const FilegateCapabilities(
        supportsFilePicking: true,
        supportsDirectoryPicking: true,
        supportsMixedPicking: true,
        supportsInitialDirectory: true,
        supportsPersistedAccess: true,
        supportsNativeUriRead: false,
        supportsFileSaving: true,
        supportsFileWriting: true,
        supportsFileStreamWriting: true,
      ),
      'windows' => const FilegateCapabilities(
        supportsFilePicking: true,
        supportsDirectoryPicking: true,
        supportsMixedPicking: false,
        supportsInitialDirectory: true,
        supportsPersistedAccess: true,
        supportsNativeUriRead: false,
        supportsFileSaving: true,
        supportsFileWriting: true,
        supportsFileStreamWriting: true,
      ),
      'linux' => const FilegateCapabilities(
        supportsFilePicking: true,
        supportsDirectoryPicking: true,
        supportsMixedPicking: false,
        supportsInitialDirectory: true,
        supportsPersistedAccess: true,
        supportsNativeUriRead: false,
        supportsFileSaving: true,
        supportsFileWriting: true,
        supportsFileStreamWriting: true,
      ),
      _ => const FilegateCapabilities(
        supportsFilePicking: false,
        supportsDirectoryPicking: false,
        supportsMixedPicking: false,
        supportsInitialDirectory: false,
        supportsPersistedAccess: false,
        supportsNativeUriRead: false,
      ),
    };
  }

  @override
  Future<List<PickedEntry>?> pick(FilegatePickOptions options) async {
    final entries = await methodChannel.invokeListMethod<Object?>(
      'pick',
      options.toMap(),
    );

    return _decodePickedEntries(entries);
  }

  @override
  Future<List<PickedEntry>?> pickMedia(FilegateMediaPickOptions options) async {
    final entries = await methodChannel.invokeListMethod<Object?>(
      'pickMedia',
      options.toMap(),
    );

    return _decodePickedEntries(entries);
  }

  List<PickedEntry>? _decodePickedEntries(List<Object?>? entries) {
    if (entries == null) {
      return null;
    }

    final uniqueEntries = <String, PickedEntry>{};
    for (final entry in entries) {
      final decodedEntry = PickedEntry.fromMap(_castMap(entry));
      uniqueEntries.putIfAbsent(decodedEntry.path, () => decodedEntry);
    }

    return uniqueEntries.values.toList(growable: false)
      ..sort(_comparePickedEntries);
  }

  @override
  Future<PickedEntry?> save(FilegateSaveOptions options) async {
    if (options.suggestedName.trim().isEmpty) {
      throw ArgumentError.value(
        options.suggestedName,
        'suggestedName',
        'suggestedName must not be empty',
      );
    }
    if (options.suggestedName.contains('/') ||
        options.suggestedName.contains(r'\')) {
      throw ArgumentError.value(
        options.suggestedName,
        'suggestedName',
        'suggestedName must be a file name, not a path',
      );
    }

    final entry = await methodChannel.invokeMapMethod<Object?, Object?>(
      'save',
      options.toMap(),
    );

    if (entry == null) {
      return null;
    }

    return PickedEntry.fromMap(entry);
  }

  @override
  Future<FilegateGallerySaveResult> saveToGallery(
    FilegateGallerySaveOptions options,
  ) async {
    if (_operatingSystem != 'android' && _operatingSystem != 'ios') {
      throw PlatformException(
        code: FilegateErrorCode.unsupportedMode,
        message:
            'Saving media to the system gallery is supported on Android and iOS only.',
      );
    }

    final result = await methodChannel.invokeMapMethod<Object?, Object?>(
      'saveToGallery',
      options.toMap(),
    );

    return FilegateGallerySaveResult.fromMap(_castMap(result));
  }

  @override
  Future<PickedEntry> write(FilegateWriteOptions options) async {
    if (options.path.isEmpty) {
      throw ArgumentError.value(options.path, 'path', 'path must not be empty');
    }

    final entry = await methodChannel.invokeMapMethod<Object?, Object?>(
      'write',
      options.toMap(),
    );

    return PickedEntry.fromMap(_castMap(entry));
  }

  @override
  Future<FileWriteSession> openWrite(
    String path, {
    FilegateWriteMode mode = FilegateWriteMode.replace,
  }) async {
    if (path.isEmpty) {
      throw ArgumentError.value(path, 'path', 'path must not be empty');
    }

    final sessionId = await methodChannel.invokeMethod<String>('startWrite', {
      'path': path,
      'mode': mode.name,
    });

    if (sessionId == null || sessionId.isEmpty) {
      throw PlatformException(
        code: FilegateErrorCode.missingWriteSessionId,
        message: 'Native writer did not return a session identifier.',
      );
    }

    return FileWriteSession(
      onAdd: (chunk) {
        return methodChannel.invokeMethod<void>('writeChunk', {
          'sessionId': sessionId,
          'bytes': chunk,
        });
      },
      onClose: () async {
        final entry = await methodChannel.invokeMapMethod<Object?, Object?>(
          'finishWrite',
          {'sessionId': sessionId},
        );
        return PickedEntry.fromMap(_castMap(entry));
      },
      onCancel: () => _cancelWrite(sessionId),
    );
  }

  @override
  Future<int?> getFileSize(String path) async {
    if (path.isEmpty) {
      throw ArgumentError.value(path, 'path', 'path must not be empty');
    }

    final size = await methodChannel.invokeMethod<num?>('getFileSize', {
      'path': path,
    });
    return size?.toInt();
  }

  @override
  FileReadSession<Uint8List> openRead(
    String path, {
    int chunkSize = 64 * 1024,
    int start = 0,
    int? end,
  }) {
    validateReadArguments(path, chunkSize: chunkSize, start: start, end: end);

    if (!forceNativeRead &&
        (_operatingSystem == 'macos' ||
            _operatingSystem == 'windows' ||
            _operatingSystem == 'linux')) {
      return _openDesktopRead(
        path,
        chunkSize: chunkSize,
        start: start,
        end: end,
      );
    }

    StreamSubscription<dynamic>? subscription;
    String? streamId;
    Future<String?>? startReadFuture;
    bool cancelled = false;
    bool closed = false;
    Future<void>? cancelFuture;
    Future<void>? nativeCancelFuture;
    bool awaitingAcknowledgement = false;

    late final StreamController<Uint8List> controller;
    late final Future<void> Function() cancelOnce;
    void acknowledgeChunk() {
      if (!awaitingAcknowledgement ||
          controller.isPaused ||
          cancelled ||
          closed) {
        return;
      }
      awaitingAcknowledgement = false;
      unawaited(() async {
        try {
          await methodChannel.invokeMethod<void>('ackRead', {
            'streamId': streamId,
          });
        } catch (error, stackTrace) {
          if (!cancelled && !closed) {
            controller.addError(error, stackTrace);
            await cancelOnce();
          }
        }
      }());
    }

    void addChunk(Uint8List chunk) {
      if (cancelled || closed) return;
      controller.add(chunk);
      awaitingAcknowledgement = true;
      // Let delivery (and async consumers pausing the stream) run first.
      scheduleMicrotask(acknowledgeChunk);
    }

    Future<void> cancelStartedRead() async {
      final activeStreamId = streamId;
      if (activeStreamId != null && activeStreamId.isNotEmpty) {
        nativeCancelFuture ??= _cancelRead(activeStreamId);
        await nativeCancelFuture;
        return;
      }

      final pendingStartRead = startReadFuture;
      if (pendingStartRead == null) {
        return;
      }

      try {
        final pendingStreamId = await pendingStartRead;
        if (pendingStreamId != null && pendingStreamId.isNotEmpty) {
          nativeCancelFuture ??= _cancelRead(pendingStreamId);
          await nativeCancelFuture;
        }
      } on Object {
        // If startRead itself failed, there is no native stream to cancel.
      }
    }

    controller = StreamController<Uint8List>(
      onListen: () async {
        try {
          startReadFuture = methodChannel.invokeMethod<String>('startRead', {
            'path': path,
            'chunkSize': chunkSize,
            'start': start,
            'end': end,
            'flowControlled': true,
          });
          streamId = await startReadFuture;

          if (streamId == null || streamId!.isEmpty) {
            throw PlatformException(
              code: FilegateErrorCode.missingStreamId,
              message: 'Native reader did not return a stream identifier.',
            );
          }

          if (cancelled) {
            await cancelStartedRead();
            return;
          }

          subscription = EventChannel('$_readChannelPrefix/$streamId')
              .receiveBroadcastStream()
              .listen(
                (event) {
                  if (cancelled || closed) return;
                  if (event is Uint8List) {
                    addChunk(event);
                    return;
                  }
                  if (event is ByteData) {
                    addChunk(
                      event.buffer.asUint8List(
                        event.offsetInBytes,
                        event.lengthInBytes,
                      ),
                    );
                    return;
                  }
                  if (event is List && event.every((item) => item is int)) {
                    addChunk(Uint8List.fromList(event.cast<int>()));
                    return;
                  }

                  controller.addError(
                    PlatformException(
                      code: FilegateErrorCode.invalidChunk,
                      message:
                          'Unexpected native chunk type: ${event.runtimeType}.',
                    ),
                  );
                  unawaited(cancelOnce());
                },
                onError: (Object error, StackTrace stackTrace) {
                  if (cancelled || closed) return;
                  controller.addError(error, stackTrace);
                  unawaited(cancelOnce());
                },
                onDone: () async {
                  await _closeController(
                    controller,
                    alreadyClosed: () => closed,
                    onClose: () => closed = true,
                  );
                },
              );
          if (controller.isPaused) subscription?.pause();
        } catch (error, stackTrace) {
          if (!cancelled) {
            controller.addError(error, stackTrace);
          }
          await _closeController(
            controller,
            alreadyClosed: () => closed,
            onClose: () => closed = true,
          );
        }
      },
      onPause: () => subscription?.pause(),
      onResume: () {
        subscription?.resume();
        scheduleMicrotask(acknowledgeChunk);
      },
      onCancel: () => cancelOnce(),
    );

    cancelOnce = () {
      return cancelFuture ??= () async {
        cancelled = true;
        await _cancelEventSubscription(subscription);
        await cancelStartedRead();
        unawaited(
          _closeController(
            controller,
            alreadyClosed: () => closed,
            onClose: () => closed = true,
          ),
        );
      }();
    };

    return FileReadSession<Uint8List>(
      stream: controller.stream,
      onCancel: cancelOnce,
    );
  }

  FileReadSession<Uint8List> _openDesktopRead(
    String path, {
    required int chunkSize,
    required int start,
    required int? end,
  }) {
    RandomAccessFile? file;
    bool cancelled = false;
    bool closed = false;
    Future<void>? readFuture;
    Future<void>? cancelFuture;
    Completer<void>? resume;
    late final StreamController<Uint8List> controller;

    void closeController() {
      if (closed) return;
      closed = true;
      // Completion can wait for a paused listener. Cleanup must not wait for it.
      unawaited(controller.close());
    }

    Future<void> read() async {
      var opened = false;
      try {
        final localPath = path.toLowerCase().startsWith('file:')
            ? PickedEntry(
                path: path,
                name: path,
                kind: PickedEntryKind.file,
              ).fileSystemPath
            : path;
        if (localPath == null) {
          throw PlatformException(
            code: FilegateErrorCode.unsupportedMode,
            message: 'The provided identifier is not a local file path.',
            details: path,
          );
        }
        final type = await FileSystemEntity.type(localPath);
        if (cancelled) return;
        if (type == FileSystemEntityType.notFound) {
          throw PlatformException(
            code: FilegateErrorCode.pathNotFound,
            message: 'The provided path does not exist.',
            details: path,
          );
        }
        if (type == FileSystemEntityType.directory) {
          throw PlatformException(
            code: FilegateErrorCode.notAFile,
            message: 'The provided path is a directory, not a file.',
            details: path,
          );
        }

        final handle = await File(localPath).open();
        file = handle;
        opened = true;
        if (cancelled) return;
        final length = await handle.length();
        final endOffset = end == null || end > length ? length : end;
        if (cancelled || start >= endOffset) return;

        var offset = start;
        await handle.setPosition(offset);
        while (!cancelled && offset < endOffset) {
          while (!cancelled && controller.isPaused) {
            await (resume ??= Completer<void>()).future;
          }
          if (cancelled) break;
          final remainingBytes = endOffset - offset;
          final currentChunkSize = remainingBytes < chunkSize
              ? remainingBytes
              : chunkSize;
          final chunk = await handle.read(currentChunkSize);
          if (cancelled || chunk.isEmpty) break;
          offset += chunk.length;
          controller.add(chunk);
        }
      } catch (error, stackTrace) {
        if (!cancelled) {
          Object mapped = error;
          if (error is FileSystemException) {
            final osCode = error.osError?.errorCode;
            final missing = osCode == 2 || (Platform.isWindows && osCode == 3);
            final denied = Platform.isWindows
                ? osCode == 5
                : osCode == 1 || osCode == 13;
            mapped = PlatformException(
              code: missing
                  ? FilegateErrorCode.pathNotFound
                  : denied
                  ? FilegateErrorCode.permissionDenied
                  : opened
                  ? FilegateErrorCode.readFailed
                  : FilegateErrorCode.readOpenFailed,
              message: error.message,
              details: path,
            );
          }
          controller.addError(mapped, stackTrace);
        }
      } finally {
        try {
          await file?.close();
        } catch (error, stackTrace) {
          if (!cancelled) controller.addError(error, stackTrace);
        }
        file = null;
        closeController();
      }
    }

    Future<void> cancelOnce() {
      return cancelFuture ??= () async {
        cancelled = true;
        resume?.complete();
        resume = null;
        // The producer owns the handle, including pending open/read operations.
        await readFuture;
        closeController();
      }();
    }

    controller = StreamController<Uint8List>(
      onListen: () {
        if (!cancelled) readFuture = read();
      },
      onResume: () {
        resume?.complete();
        resume = null;
      },
      onCancel: cancelOnce,
    );
    return FileReadSession<Uint8List>(
      stream: controller.stream,
      onCancel: cancelOnce,
    );
  }

  Future<void> _cancelRead(String streamId) async {
    try {
      await methodChannel.invokeMethod<void>('cancelRead', {
        'streamId': streamId,
      });
    } on PlatformException {
      // Ignore cancellation failures because the consumer already requested
      // shutdown and the native stream may have ended naturally.
    }
  }

  static Future<void> _cancelEventSubscription(
    StreamSubscription<dynamic>? subscription,
  ) async {
    try {
      await subscription?.cancel();
    } on MissingPluginException {
      // Ignore cancellation failures because the native dynamic event channel
      // may have ended and been released before Dart observes stream teardown.
    } on PlatformException {
      // Ignore cancellation failures because the consumer already requested
      // shutdown and the native stream may have ended naturally.
    }
  }

  Future<void> _cancelWrite(String sessionId) async {
    try {
      await methodChannel.invokeMethod<void>('cancelWrite', {
        'sessionId': sessionId,
      });
    } on PlatformException {
      // Ignore cancellation failures because the consumer already requested
      // shutdown and the native write session may have ended naturally.
    }
  }

  static Future<void> _closeController(
    StreamController<Uint8List> controller, {
    required bool Function() alreadyClosed,
    required VoidCallback onClose,
  }) async {
    if (alreadyClosed()) {
      return;
    }
    onClose();
    await controller.close();
  }

  static Map<Object?, Object?> _castMap(Object? value) {
    if (value is Map<Object?, Object?>) {
      return value;
    }
    throw ArgumentError.value(
      value,
      'value',
      'Expected a map from the native layer',
    );
  }

  static int _comparePickedEntries(PickedEntry left, PickedEntry right) {
    final keyComparison = _pickedEntrySortKey(
      left,
    ).compareTo(_pickedEntrySortKey(right));
    if (keyComparison != 0) {
      return keyComparison;
    }
    final nameComparison = left.name.compareTo(right.name);
    if (nameComparison != 0) {
      return nameComparison;
    }
    return left.path.compareTo(right.path);
  }

  static String _pickedEntrySortKey(PickedEntry entry) {
    return entry.relativePath?.replaceAll(r'\', '/') ?? entry.name;
  }
}
