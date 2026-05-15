import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'filegate_platform_interface.dart';
import 'src/file_read_session.dart';
import 'src/models.dart';

/// An implementation of [FilegatePlatform] that uses method channels.
class MethodChannelFilegate extends FilegatePlatform {
  MethodChannelFilegate({@visibleForTesting bool forceNativeRead = false})
    : _forceNativeRead = forceNativeRead;

  static const _readChannelPrefix = 'filegate/read';
  final bool _forceNativeRead;

  @visibleForTesting
  final methodChannel = const MethodChannel('filegate');

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

    return uniqueEntries.values.toList(growable: false);
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

    if (!_forceNativeRead &&
        (Platform.isMacOS || Platform.isWindows || Platform.isLinux)) {
      return _openDesktopRead(path, chunkSize: chunkSize, start: start);
    }

    StreamSubscription<dynamic>? subscription;
    String? streamId;
    bool cancelled = false;
    bool closed = false;
    Future<void>? cancelFuture;

    late final StreamController<Uint8List> controller;
    late final Future<void> Function() cancelOnce;
    controller = StreamController<Uint8List>(
      onListen: () async {
        try {
          streamId = await methodChannel.invokeMethod<String>('startRead', {
            'path': path,
            'chunkSize': chunkSize,
            'start': start,
          });

          if (streamId == null || streamId!.isEmpty) {
            throw PlatformException(
              code: 'missing_stream_id',
              message: 'Native reader did not return a stream identifier.',
            );
          }

          if (cancelled) {
            await _cancelRead(streamId!);
            await _closeController(
              controller,
              alreadyClosed: () => closed,
              onClose: () => closed = true,
            );
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
                      code: 'invalid_chunk',
                      message:
                          'Unexpected native chunk type: ${event.runtimeType}.',
                    ),
                  );
                },
                onError: controller.addError,
                onDone: () async {
                  await _closeController(
                    controller,
                    alreadyClosed: () => closed,
                    onClose: () => closed = true,
                  );
                },
              );
        } catch (error, stackTrace) {
          controller.addError(error, stackTrace);
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
        await subscription?.cancel();
        if (streamId != null && streamId!.isNotEmpty) {
          await _cancelRead(streamId!);
        }
        await _closeController(
          controller,
          alreadyClosed: () => closed,
          onClose: () => closed = true,
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
            code: 'path_not_found',
            message: 'The provided path does not exist.',
            details: path,
          );
        }
        if (type == FileSystemEntityType.directory) {
          throw PlatformException(
            code: 'not_a_file',
            message: 'The provided path is a directory, not a file.',
            details: path,
          );
        }

        file = await File(path).open();
        final length = await file!.length();
        if (start > length) {
          await closeController();
          return;
        }

        var offset = start;
        await file!.setPosition(offset);
        while (!cancelled && offset < length) {
          final remainingBytes = length - offset;
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
}
