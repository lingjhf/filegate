import 'dart:typed_data';

import 'package:flutter/services.dart';

export 'src/errors.dart';
export 'src/file_read_session.dart';
export 'src/models.dart';

import 'filegate_platform_interface.dart';
import 'src/file_read_session.dart';
import 'src/models.dart';

class Filegate {
  const Filegate();

  Future<FilegateCapabilities> getCapabilities() {
    return FilegatePlatform.instance.getCapabilities();
  }

  Future<List<PickedEntry>?> pick(FilegatePickOptions options) {
    return FilegatePlatform.instance.pick(options);
  }

  Future<List<PickedEntry>?> pickFiles({
    bool allowMultiple = false,
    List<String> allowedExtensions = const [],
    String? title,
    String? initialDirectory,
    bool persistAccess = true,
  }) {
    return pick(
      FilegatePickOptions(
        selectionMode: FilegateSelectionMode.filesOnly,
        allowMultiple: allowMultiple,
        allowedExtensions: allowedExtensions,
        title: title,
        initialDirectory: initialDirectory,
        persistAccess: persistAccess,
      ),
    );
  }

  Future<List<PickedEntry>?> pickDirectoryFiles({
    bool recursive = false,
    List<String> allowedExtensions = const [],
    String? title,
    String? initialDirectory,
    bool persistAccess = true,
  }) {
    return pick(
      FilegatePickOptions(
        selectionMode: FilegateSelectionMode.directoriesOnly,
        recursive: recursive,
        allowedExtensions: allowedExtensions,
        title: title,
        initialDirectory: initialDirectory,
        persistAccess: persistAccess,
      ),
    );
  }

  Future<List<PickedEntry>?> pickMixed({
    bool allowMultiple = false,
    bool recursive = false,
    List<String> allowedExtensions = const [],
    String? title,
    String? initialDirectory,
    bool persistAccess = true,
  }) {
    return pick(
      FilegatePickOptions(
        selectionMode: FilegateSelectionMode.filesAndDirectories,
        allowMultiple: allowMultiple,
        recursive: recursive,
        allowedExtensions: allowedExtensions,
        title: title,
        initialDirectory: initialDirectory,
        persistAccess: persistAccess,
      ),
    );
  }

  Future<int?> getFileSize(String path) {
    return FilegatePlatform.instance.getFileSize(path);
  }

  FileReadSession<FileReadChunk> openReadWithProgress(
    String path, {
    int chunkSize = 64 * 1024,
    int start = 0,
    int? end,
  }) {
    final baseSession = openRead(
      path,
      chunkSize: chunkSize,
      start: start,
      end: end,
    );

    late final Stream<FileReadChunk> progressStream;
    progressStream = (() async* {
      int? totalBytes;
      try {
        totalBytes = _rangeTotalBytes(await getFileSize(path), start, end);
      } on PlatformException {
        totalBytes = null;
      }
      var bytesRead = 0;

      await for (final chunk in baseSession.stream) {
        bytesRead += chunk.length;
        yield FileReadChunk(
          data: chunk,
          bytesRead: bytesRead,
          totalBytes: totalBytes,
        );
      }
    })();

    return FileReadSession<FileReadChunk>(
      stream: progressStream,
      onCancel: baseSession.cancel,
    );
  }

  FileReadSession<Uint8List> openRead(
    String path, {
    int chunkSize = 64 * 1024,
    int start = 0,
    int? end,
  }) {
    return FilegatePlatform.instance.openRead(
      path,
      chunkSize: chunkSize,
      start: start,
      end: end,
    );
  }

  Future<Uint8List> readAllBytes(
    String path, {
    int chunkSize = 64 * 1024,
    int? maxBytes,
  }) async {
    final session = openRead(path, chunkSize: chunkSize);
    final builder = BytesBuilder(copy: false);

    try {
      await for (final chunk in session.stream) {
        builder.add(chunk);
        if (maxBytes != null && builder.length > maxBytes) {
          await session.cancel();
          throw StateError('readAllBytes exceeded maxBytes ($maxBytes).');
        }
      }
    } catch (_) {
      await session.cancel();
      rethrow;
    }

    return builder.takeBytes();
  }

  Future<Uint8List> readByteRange(
    String path, {
    required int start,
    required int length,
    int chunkSize = 64 * 1024,
  }) async {
    if (start < 0) {
      throw ArgumentError.value(start, 'start', 'start must not be negative');
    }
    if (length < 0) {
      throw ArgumentError.value(
        length,
        'length',
        'length must not be negative',
      );
    }
    if (chunkSize <= 0) {
      throw ArgumentError.value(
        chunkSize,
        'chunkSize',
        'chunkSize must be greater than zero',
      );
    }
    if (length == 0) {
      return Uint8List(0);
    }

    final session = openRead(
      path,
      chunkSize: chunkSize < length ? chunkSize : length,
      start: start,
      end: start + length,
    );
    final builder = BytesBuilder(copy: false);

    try {
      await for (final chunk in session.stream) {
        final remaining = length - builder.length;
        if (remaining <= 0) {
          break;
        }
        if (chunk.length <= remaining) {
          builder.add(chunk);
        } else {
          builder.add(Uint8List.sublistView(chunk, 0, remaining));
          break;
        }
      }
    } catch (_) {
      await session.cancel();
      rethrow;
    }

    return builder.takeBytes();
  }
}

int? _rangeTotalBytes(int? fileSize, int start, int? end) {
  if (fileSize == null) {
    return null;
  }
  final effectiveEnd = end == null || end > fileSize ? fileSize : end;
  if (start >= effectiveEnd) {
    return 0;
  }
  return effectiveEnd - start;
}
