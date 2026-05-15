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
  }) {
    return pick(
      FilegatePickOptions(
        selectionMode: FilegateSelectionMode.filesOnly,
        allowMultiple: allowMultiple,
        allowedExtensions: allowedExtensions,
        title: title,
        initialDirectory: initialDirectory,
      ),
    );
  }

  Future<List<PickedEntry>?> pickDirectoryFiles({
    bool recursive = false,
    List<String> allowedExtensions = const [],
    String? title,
    String? initialDirectory,
  }) {
    return pick(
      FilegatePickOptions(
        selectionMode: FilegateSelectionMode.directoriesOnly,
        recursive: recursive,
        allowedExtensions: allowedExtensions,
        title: title,
        initialDirectory: initialDirectory,
      ),
    );
  }

  Future<List<PickedEntry>?> pickMixed({
    bool allowMultiple = false,
    bool recursive = false,
    List<String> allowedExtensions = const [],
    String? title,
    String? initialDirectory,
  }) {
    return pick(
      FilegatePickOptions(
        selectionMode: FilegateSelectionMode.filesAndDirectories,
        allowMultiple: allowMultiple,
        recursive: recursive,
        allowedExtensions: allowedExtensions,
        title: title,
        initialDirectory: initialDirectory,
      ),
    );
  }

  Future<int?> getFileSize(String path) {
    return FilegatePlatform.instance.getFileSize(path);
  }

  FileReadSession<FileReadChunk> openReadWithProgress(
    String path, {
    int chunkSize = 64 * 1024,
  }) {
    final baseSession = openRead(path, chunkSize: chunkSize);

    late final Stream<FileReadChunk> progressStream;
    progressStream = (() async* {
      int? totalBytes;
      try {
        totalBytes = await getFileSize(path);
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
  }) {
    return FilegatePlatform.instance.openRead(
      path,
      chunkSize: chunkSize,
      start: start,
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
}
