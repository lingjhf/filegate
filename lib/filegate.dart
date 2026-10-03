import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

export 'src/errors.dart';
export 'src/file_read_session.dart';
export 'src/file_write_session.dart';
export 'src/models.dart';

import 'filegate_platform_interface.dart';
import 'src/errors.dart';
import 'src/extensions.dart';
import 'src/file_arguments.dart';
import 'src/file_read_session.dart';
import 'src/file_write_session.dart';
import 'src/models.dart';
import 'src/read_arguments.dart';

class Filegate {
  const Filegate();

  Future<FilegateCapabilities> getCapabilities() {
    return FilegatePlatform.instance.getCapabilities();
  }

  Future<List<PickedEntry>?> pick(FilegatePickOptions options) {
    return FilegatePlatform.instance.pick(options);
  }

  Future<List<PickedEntry>?> pickMedia(FilegateMediaPickOptions options) {
    return FilegatePlatform.instance.pickMedia(options);
  }

  Future<PickedEntry?> save(FilegateSaveOptions options) {
    validateFileName(options.suggestedName, argumentName: 'suggestedName');
    return FilegatePlatform.instance.save(options);
  }

  Future<FilegateGallerySaveResult> saveToGallery(
    Uint8List bytes, {
    required String fileName,
    String? mimeType,
  }) {
    final mediaType = _galleryMediaTypeFor(fileName, mimeType);
    final options = FilegateGallerySaveOptions(
      bytes: bytes,
      fileName: fileName,
      mediaType: mediaType,
      mimeType: mimeType,
    );
    _validateGallerySaveOptions(options);
    return FilegatePlatform.instance.saveToGallery(options);
  }

  Future<PickedEntry> write(FilegateWriteOptions options) {
    validateNonEmptyPath(options.path);
    return FilegatePlatform.instance.write(options);
  }

  Future<PickedEntry> writeFile(
    String path,
    Uint8List bytes, {
    FilegateWriteMode mode = FilegateWriteMode.replace,
  }) {
    return write(FilegateWriteOptions(path: path, bytes: bytes, mode: mode));
  }

  Future<FileWriteSession> openWrite(
    String path, {
    FilegateWriteMode mode = FilegateWriteMode.replace,
    int? totalBytes,
    FilegateWriteProgressCallback? onProgress,
  }) async {
    validateNonEmptyPath(path);
    validateWriteProgressTotalBytes(totalBytes);
    final session = await FilegatePlatform.instance.openWrite(path, mode: mode);
    if (onProgress == null) {
      return session;
    }
    session.addProgressListener(onProgress, totalBytes: totalBytes);
    return session;
  }

  Future<PickedEntry> writeStream(
    String path,
    Stream<List<int>> chunks, {
    FilegateWriteMode mode = FilegateWriteMode.replace,
    int? totalBytes,
    FilegateWriteProgressCallback? onProgress,
  }) async {
    final session = await openWrite(
      path,
      mode: mode,
      totalBytes: totalBytes,
      onProgress: onProgress,
    );
    try {
      await session.addStream(chunks);
      return await session.close();
    } catch (_) {
      await session.cancel();
      rethrow;
    }
  }

  Future<PickedEntry?> saveFile(
    Uint8List bytes, {
    required String suggestedName,
    List<String> allowedExtensions = const [],
    String? title,
    String? initialDirectory,
    String? mimeType,
    bool persistAccess = true,
  }) {
    return save(
      FilegateSaveOptions(
        bytes: bytes,
        suggestedName: suggestedName,
        allowedExtensions: allowedExtensions,
        title: title,
        initialDirectory: initialDirectory,
        mimeType: mimeType,
        persistAccess: persistAccess,
      ),
    );
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

  /// Selects a directory itself, including an empty directory.
  ///
  /// Returns `null` when cancelled. On Android the entry identifies a document
  /// tree URI; [PickedEntry.fileSystemPath] is available for local paths.
  Future<PickedEntry?> pickDirectory({
    String? title,
    String? initialDirectory,
    String? confirmButtonText,
    bool persistAccess = true,
  }) async {
    final entries = await pick(
      FilegatePickOptions(
        selectionMode: FilegateSelectionMode.directoriesOnly,
        enumerateDirectories: false,
        title: title,
        initialDirectory: initialDirectory,
        confirmButtonText: confirmButtonText,
        persistAccess: persistAccess,
      ),
    );
    if (entries == null) return null;
    if (entries.length != 1 || !entries.single.isDirectory) {
      throw PlatformException(
        code: 'invalid_response',
        message: 'Expected a single directory entry.',
      );
    }
    return entries.single;
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

  Future<List<PickedEntry>?> pickImages({
    int selectionLimit = 1,
    bool persistAccess = true,
  }) {
    return pickMedia(
      FilegateMediaPickOptions(
        mediaType: FilegateMediaType.images,
        selectionLimit: selectionLimit,
        persistAccess: persistAccess,
      ),
    );
  }

  Future<List<PickedEntry>?> pickVideos({
    int selectionLimit = 1,
    bool persistAccess = true,
  }) {
    return pickMedia(
      FilegateMediaPickOptions(
        mediaType: FilegateMediaType.videos,
        selectionLimit: selectionLimit,
        persistAccess: persistAccess,
      ),
    );
  }

  Future<List<PickedEntry>?> pickImagesAndVideos({
    int selectionLimit = 1,
    bool persistAccess = true,
  }) {
    return pickMedia(
      FilegateMediaPickOptions(
        selectionLimit: selectionLimit,
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
      } on Object {
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
    validateReadArguments(path, chunkSize: chunkSize, start: start, end: end);
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
    if (maxBytes != null && maxBytes < 0) {
      throw ArgumentError.value(
        maxBytes,
        'maxBytes',
        'maxBytes must not be negative',
      );
    }

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
    validateNonEmptyPath(directoryPath, argumentName: 'directoryPath');

    final type = await FileSystemEntity.type(directoryPath);
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

    final normalizedExtensions = normalizeExtensions(allowedExtensions);
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

void _validateGallerySaveOptions(FilegateGallerySaveOptions options) {
  if (options.bytes.isEmpty) {
    throw ArgumentError.value(
      options.bytes,
      'bytes',
      'bytes must not be empty',
    );
  }
  validateFileName(options.fileName, argumentName: 'fileName');
}

FilegateGalleryMediaType _galleryMediaTypeFor(
  String fileName,
  String? mimeType,
) {
  final normalizedMimeType = mimeType?.trim().toLowerCase();
  if (normalizedMimeType != null && normalizedMimeType.isNotEmpty) {
    if (normalizedMimeType.startsWith('image/')) {
      return FilegateGalleryMediaType.image;
    }
    if (normalizedMimeType.startsWith('video/')) {
      return FilegateGalleryMediaType.video;
    }
    throw PlatformException(
      code: FilegateErrorCode.unsupportedMode,
      message: 'Only image and video files can be saved to the system gallery.',
      details: mimeType,
    );
  }

  final extension = _extension(fileName);
  if (extension != null) {
    if (_imageGalleryExtensions.contains(extension)) {
      return FilegateGalleryMediaType.image;
    }
    if (_videoGalleryExtensions.contains(extension)) {
      return FilegateGalleryMediaType.video;
    }
  }

  throw PlatformException(
    code: FilegateErrorCode.unsupportedMode,
    message: 'Only image and video files can be saved to the system gallery.',
    details: mimeType ?? fileName,
  );
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

bool _matchesAllowedExtensions(String path, Set<String> allowedExtensions) {
  if (allowedExtensions.isEmpty) {
    return true;
  }
  final extension = _extension(path);
  return extension != null && allowedExtensions.contains(extension);
}

String _basename(String path) => p.basename(path);

String _relativePath(String rootPath, String childPath) =>
    p.posix.joinAll(p.split(p.relative(childPath, from: rootPath)));

String? _extension(String path) {
  final extension = p.extension(path).toLowerCase();
  return extension.length > 1 ? extension.substring(1) : null;
}

const _imageGalleryExtensions = <String>{
  'jpg',
  'jpeg',
  'png',
  'gif',
  'heic',
  'heif',
  'webp',
  'bmp',
};

const _videoGalleryExtensions = <String>{
  'mp4',
  'mov',
  'm4v',
  '3gp',
  '3gpp',
  'avi',
  'mkv',
  'webm',
};
