import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';

export 'src/errors.dart';
export 'src/file_read_session.dart';
export 'src/models.dart';

import 'filegate_platform_interface.dart';
import 'src/errors.dart';
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

  Future<List<PickedEntry>> listDirectoryFiles(
    String directoryPath, {
    bool recursive = false,
    List<String> allowedExtensions = const [],
  }) async {
    if (directoryPath.isEmpty) {
      throw ArgumentError.value(
        directoryPath,
        'directoryPath',
        'directoryPath must not be empty',
      );
    }

    final type = FileSystemEntity.typeSync(directoryPath);
    if (type == FileSystemEntityType.notFound) {
      throw PlatformException(
        code: FilegateErrorCode.pathNotFound,
        message: 'The provided directory path does not exist.',
        details: directoryPath,
      );
    }
    if (type != FileSystemEntityType.directory) {
      throw PlatformException(
        code: FilegateErrorCode.notADirectory,
        message: 'The provided path is not a directory.',
        details: directoryPath,
      );
    }

    final normalizedExtensions = _normalizeAllowedExtensions(allowedExtensions);
    final root = Directory(directoryPath);
    final entries = <PickedEntry>[];

    try {
      await for (final entity in root.list(
        recursive: recursive,
        followLinks: false,
      )) {
        if (entity is! File) {
          continue;
        }
        if (!_matchesAllowedExtensions(entity.path, normalizedExtensions)) {
          continue;
        }

        final stat = await entity.stat();
        entries.add(
          PickedEntry(
            path: entity.path,
            name: _basename(entity.path),
            kind: PickedEntryKind.file,
            relativePath: _relativePath(directoryPath, entity.path),
            metadata: PickedEntryMetadata(
              size: stat.size,
              modifiedAt: stat.modified.toUtc(),
            ),
          ),
        );
      }
    } on FileSystemException catch (error) {
      throw PlatformException(
        code: FilegateErrorCode.enumerationFailed,
        message: error.message,
        details: directoryPath,
      );
    }

    entries.sort(
      (left, right) => left.relativePath!.compareTo(right.relativePath!),
    );
    return entries;
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

List<String> _normalizeAllowedExtensions(List<String> extensions) {
  return extensions
      .map(
        (extension) =>
            extension.startsWith('.') ? extension.substring(1) : extension,
      )
      .map((extension) => extension.toLowerCase())
      .where((extension) => extension.isNotEmpty)
      .toList(growable: false);
}

bool _matchesAllowedExtensions(String path, List<String> allowedExtensions) {
  if (allowedExtensions.isEmpty) {
    return true;
  }
  final extension = _extension(path);
  return extension != null && allowedExtensions.contains(extension);
}

String _basename(String path) {
  final normalized = path.replaceAll(r'\', '/');
  return normalized.split('/').where((part) => part.isNotEmpty).last;
}

String _relativePath(String rootPath, String childPath) {
  final root = rootPath.replaceAll(r'\', '/').replaceFirst(RegExp(r'/+$'), '');
  final child = childPath.replaceAll(r'\', '/');
  final prefix = '$root/';
  if (child.startsWith(prefix)) {
    return child.substring(prefix.length);
  }
  return _basename(childPath);
}

String? _extension(String path) {
  final name = _basename(path);
  final dotIndex = name.lastIndexOf('.');
  if (dotIndex <= 0 || dotIndex == name.length - 1) {
    return null;
  }
  return name.substring(dotIndex + 1).toLowerCase();
}
