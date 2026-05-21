import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'filegate_platform_interface.dart';
import 'src/errors.dart';
import 'src/file_read_session.dart';
import 'src/file_write_session.dart';
import 'src/models.dart';

/// An implementation of [FilegatePlatform] that uses method channels.
class MethodChannelFilegate extends FilegatePlatform {
  MethodChannelFilegate({@visibleForTesting this._forceNativeRead = false});

  static const _readChannelPrefix = 'filegate/read';
  final bool _forceNativeRead;

  @visibleForTesting
  final methodChannel = const MethodChannel('filegate');

  @override
  Future<FilegateCapabilities> getCapabilities() async {
    return capabilitiesForOperatingSystem(Platform.operatingSystem);
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
    if (path.isEmpty) {
      throw ArgumentError.value(path, 'path', 'path must not be empty');
    }
    if (chunkSize <= 0) {
      throw ArgumentError.value(
        chunkSize,
        'chunkSize',
        'chunkSize must be greater than zero',
      );
    }
    if (start < 0) {
      throw ArgumentError.value(start, 'start', 'start must not be negative');
    }
    if (end != null && end < start) {
      throw ArgumentError.value(
        end,
        'end',
        'end must be greater than or equal to start',
      );
    }

    if (!_forceNativeRead &&
        (Platform.isMacOS || Platform.isWindows || Platform.isLinux)) {
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

    late final StreamController<Uint8List> controller;
    late final Future<void> Function() cancelOnce;
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
                  if (event is Uint8List) {
                    controller.add(event);
                    return;
                  }
                  if (event is ByteData) {
                    controller.add(event.buffer.asUint8List());
                    return;
                  }
                  if (event is List && event.every((item) => item is int)) {
                    controller.add(Uint8List.fromList(event.cast<int>()));
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
      onResume: () => subscription?.resume(),
      onCancel: () => cancelOnce(),
    );

    cancelOnce = () {
      return cancelFuture ??= () async {
        cancelled = true;
        final hasStartedStream = subscription != null || streamId != null;
        await subscription?.cancel();
        await cancelStartedRead();
        final closeFuture = _closeController(
          controller,
          alreadyClosed: () => closed,
          onClose: () => closed = true,
        );
        if (hasStartedStream) {
          await closeFuture;
        } else {
          unawaited(closeFuture);
        }
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
    final controller = StreamController<Uint8List>();
    RandomAccessFile? file;
    bool cancelled = false;
    bool closed = false;
    Future<void>? cancelFuture;

    Future<void> closeController() async {
      if (closed) return;
      closed = true;
      await controller.close();
    }

    controller.onListen = () async {
      try {
        final type = FileSystemEntity.typeSync(path);
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

        file = await File(path).open();
        final length = await file!.length();
        final endOffset = end == null || end > length ? length : end;
        if (start >= endOffset) {
          await closeController();
          return;
        }

        var offset = start;
        await file!.setPosition(offset);
        while (!cancelled && offset < endOffset) {
          final remainingBytes = endOffset - offset;
          final currentChunkSize = remainingBytes < chunkSize
              ? remainingBytes
              : chunkSize;
          final chunk = await file!.read(currentChunkSize);
          if (chunk.isEmpty) break;
          offset += chunk.length;
          if (!cancelled) {
            controller.add(Uint8List.fromList(chunk));
          }
        }
      } catch (error, stackTrace) {
        if (!cancelled) {
          controller.addError(error, stackTrace);
        }
      } finally {
        await file?.close();
        file = null;
        await closeController();
      }
    };

    Future<void> cancelOnce() {
      return cancelFuture ??= () async {
        cancelled = true;
        await file?.close();
        file = null;
        await closeController();
      }();
    }

    controller.onCancel = cancelOnce;
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
