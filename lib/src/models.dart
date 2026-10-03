import 'dart:typed_data';

import 'extensions.dart';
import 'file_location.dart';

enum FilegateSelectionMode { filesOnly, directoriesOnly, filesAndDirectories }

enum FilegateMediaType { images, videos, imagesAndVideos }

enum FilegateGalleryMediaType { image, video }

enum FilegateWriteMode { replace, append }

typedef FilegateWriteProgressCallback =
    void Function(FileWriteProgress progress);

enum PickedEntryKind { file, directory }

enum FilegateLocationKind { platformPath, fileUri, contentUri, otherUri }

class PickedEntryMetadata {
  const PickedEntryMetadata({this.size, this.modifiedAt, this.mimeType});

  static const empty = PickedEntryMetadata();

  final int? size;
  final DateTime? modifiedAt;
  final String? mimeType;

  bool get isEmpty => size == null && modifiedAt == null && mimeType == null;

  bool get isNotEmpty => !isEmpty;

  Map<String, Object?> toMap() {
    return {
      'size': size,
      'modifiedAt': modifiedAt?.millisecondsSinceEpoch,
      'mimeType': mimeType,
    };
  }

  factory PickedEntryMetadata.fromMap(Map<Object?, Object?> map) {
    final size = map['size'];
    final modifiedAt = map['modifiedAt'];
    final mimeType = map['mimeType'];

    if (size != null && (size is! int || size < 0)) {
      throw ArgumentError.value(map, 'map', 'Invalid metadata size');
    }
    if (mimeType != null && mimeType is! String) {
      throw ArgumentError.value(map, 'map', 'Invalid metadata MIME type');
    }

    return PickedEntryMetadata(
      size: size as int?,
      modifiedAt: _decodeModifiedAt(modifiedAt, map),
      mimeType: mimeType as String?,
    );
  }
}

class FilegateCapabilities {
  const FilegateCapabilities({
    required this.supportsFilePicking,
    required this.supportsDirectoryPicking,
    required this.supportsMixedPicking,
    required this.supportsInitialDirectory,
    required this.supportsPersistedAccess,
    required this.supportsNativeUriRead,
    this.supportsFileSaving = false,
    this.supportsFileWriting = false,
    this.supportsFileStreamWriting = false,
    this.supportsMediaPicking = false,
    this.supportsGallerySaving = false,
  });

  final bool supportsFilePicking;
  final bool supportsDirectoryPicking;
  final bool supportsMixedPicking;
  final bool supportsInitialDirectory;
  final bool supportsPersistedAccess;
  final bool supportsNativeUriRead;
  final bool supportsFileSaving;
  final bool supportsFileWriting;
  final bool supportsFileStreamWriting;
  final bool supportsMediaPicking;
  final bool supportsGallerySaving;

  Map<String, Object?> toMap() {
    return {
      'supportsFilePicking': supportsFilePicking,
      'supportsDirectoryPicking': supportsDirectoryPicking,
      'supportsMixedPicking': supportsMixedPicking,
      'supportsInitialDirectory': supportsInitialDirectory,
      'supportsPersistedAccess': supportsPersistedAccess,
      'supportsNativeUriRead': supportsNativeUriRead,
      'supportsFileSaving': supportsFileSaving,
      'supportsFileWriting': supportsFileWriting,
      'supportsFileStreamWriting': supportsFileStreamWriting,
      'supportsMediaPicking': supportsMediaPicking,
      'supportsGallerySaving': supportsGallerySaving,
    };
  }

  factory FilegateCapabilities.fromMap(Map<Object?, Object?> map) {
    final supportsFilePicking = map['supportsFilePicking'];
    final supportsDirectoryPicking = map['supportsDirectoryPicking'];
    final supportsMixedPicking = map['supportsMixedPicking'];
    final supportsInitialDirectory = map['supportsInitialDirectory'];
    final supportsPersistedAccess = map['supportsPersistedAccess'];
    final supportsNativeUriRead = map['supportsNativeUriRead'];
    final supportsFileSaving = map['supportsFileSaving'];
    final supportsFileWriting = map['supportsFileWriting'];
    final supportsFileStreamWriting = map['supportsFileStreamWriting'];
    final supportsMediaPicking = map['supportsMediaPicking'];
    final supportsGallerySaving = map['supportsGallerySaving'];

    if (supportsFilePicking is! bool ||
        supportsDirectoryPicking is! bool ||
        supportsMixedPicking is! bool ||
        supportsInitialDirectory is! bool ||
        supportsPersistedAccess is! bool ||
        supportsNativeUriRead is! bool ||
        (supportsFileSaving != null && supportsFileSaving is! bool) ||
        (supportsFileWriting != null && supportsFileWriting is! bool) ||
        (supportsFileStreamWriting != null &&
            supportsFileStreamWriting is! bool) ||
        (supportsMediaPicking != null && supportsMediaPicking is! bool) ||
        (supportsGallerySaving != null && supportsGallerySaving is! bool)) {
      throw ArgumentError.value(map, 'map', 'Invalid capabilities payload');
    }

    return FilegateCapabilities(
      supportsFilePicking: supportsFilePicking,
      supportsDirectoryPicking: supportsDirectoryPicking,
      supportsMixedPicking: supportsMixedPicking,
      supportsInitialDirectory: supportsInitialDirectory,
      supportsPersistedAccess: supportsPersistedAccess,
      supportsNativeUriRead: supportsNativeUriRead,
      supportsFileSaving: supportsFileSaving as bool? ?? false,
      supportsFileWriting: supportsFileWriting as bool? ?? false,
      supportsFileStreamWriting: supportsFileStreamWriting as bool? ?? false,
      supportsMediaPicking: supportsMediaPicking as bool? ?? false,
      supportsGallerySaving: supportsGallerySaving as bool? ?? false,
    );
  }
}

class FilegatePickOptions {
  const FilegatePickOptions({
    this.selectionMode = FilegateSelectionMode.filesOnly,
    this.allowMultiple = false,
    this.allowedExtensions = const [],
    this.recursive = false,
    this.enumerateDirectories = true,
    this.title,
    this.confirmButtonText,
    this.initialDirectory,
    this.persistAccess = true,
  });

  final FilegateSelectionMode selectionMode;
  final bool allowMultiple;
  final List<String> allowedExtensions;
  final bool recursive;

  /// Whether selected directories are expanded into their contained files.
  ///
  /// When `false`, the selected directory entries themselves are returned.
  final bool enumerateDirectories;
  final String? title;

  /// The confirmation button label on macOS, Windows, and Linux.
  final String? confirmButtonText;
  final String? initialDirectory;
  final bool persistAccess;

  Map<String, Object?> toMap() {
    return {
      'selectionMode': selectionMode.name,
      'allowMultiple': allowMultiple,
      'recursive': recursive,
      'enumerateDirectories': enumerateDirectories,
      'persistAccess': persistAccess,
      'allowedExtensions': normalizeExtensions(
        allowedExtensions,
      ).toList(growable: false),
      'title': title,
      'confirmButtonText': confirmButtonText,
      'initialDirectory': initialDirectory,
    };
  }
}

class FilegateMediaPickOptions {
  const FilegateMediaPickOptions({
    this.mediaType = FilegateMediaType.imagesAndVideos,
    this.selectionLimit = 1,
    this.persistAccess = true,
  });

  final FilegateMediaType mediaType;
  final int selectionLimit;
  final bool persistAccess;

  Map<String, Object?> toMap() {
    if (selectionLimit < 0) {
      throw ArgumentError.value(
        selectionLimit,
        'selectionLimit',
        'selectionLimit must not be negative',
      );
    }

    return {
      'mediaType': mediaType.name,
      'selectionLimit': selectionLimit,
      'persistAccess': persistAccess,
    };
  }
}

class FilegateSaveOptions {
  const FilegateSaveOptions({
    required this.bytes,
    required this.suggestedName,
    this.allowedExtensions = const [],
    this.title,
    this.initialDirectory,
    this.mimeType,
    this.persistAccess = true,
  });

  final Uint8List bytes;
  final String suggestedName;
  final List<String> allowedExtensions;
  final String? title;
  final String? initialDirectory;
  final String? mimeType;
  final bool persistAccess;

  Map<String, Object?> toMap() {
    return {
      'bytes': bytes,
      'suggestedName': suggestedName,
      'persistAccess': persistAccess,
      'allowedExtensions': normalizeExtensions(
        allowedExtensions,
      ).toList(growable: false),
      'title': title,
      'initialDirectory': initialDirectory,
      'mimeType': mimeType,
    };
  }
}

class FilegateGallerySaveOptions {
  const FilegateGallerySaveOptions({
    required this.bytes,
    required this.fileName,
    required this.mediaType,
    this.mimeType,
  });

  final Uint8List bytes;
  final String fileName;
  final FilegateGalleryMediaType mediaType;
  final String? mimeType;

  Map<String, Object?> toMap() {
    return {
      'bytes': bytes,
      'fileName': fileName,
      'mediaType': mediaType.name,
      'mimeType': mimeType,
    };
  }
}

class FilegateGallerySaveResult {
  const FilegateGallerySaveResult({
    required this.identifier,
    required this.name,
    required this.mediaType,
    this.mimeType,
  });

  final String identifier;
  final String name;
  final FilegateGalleryMediaType mediaType;
  final String? mimeType;

  Map<String, Object?> toMap() {
    return {
      'identifier': identifier,
      'name': name,
      'mediaType': mediaType.name,
      'mimeType': mimeType,
    };
  }

  factory FilegateGallerySaveResult.fromMap(Map<Object?, Object?> map) {
    final identifier = map['identifier'];
    final name = map['name'];
    final mediaType = map['mediaType'];
    final mimeType = map['mimeType'];

    if (identifier is! String ||
        identifier.isEmpty ||
        name is! String ||
        name.isEmpty ||
        mediaType is! String ||
        (mimeType != null && mimeType is! String)) {
      throw ArgumentError.value(
        map,
        'map',
        'Invalid gallery save result payload',
      );
    }

    return FilegateGallerySaveResult(
      identifier: identifier,
      name: name,
      mediaType: FilegateGalleryMediaType.values.byName(mediaType),
      mimeType: mimeType as String?,
    );
  }
}

class FilegateWriteOptions {
  const FilegateWriteOptions({
    required this.path,
    required this.bytes,
    this.mode = FilegateWriteMode.replace,
  });

  final String path;
  final Uint8List bytes;
  final FilegateWriteMode mode;

  Map<String, Object?> toMap() {
    return {'path': path, 'bytes': bytes, 'mode': mode.name};
  }
}

class FileWriteProgress {
  const FileWriteProgress({
    required this.bytesWritten,
    required this.totalBytes,
  });

  final int bytesWritten;
  final int? totalBytes;

  double? get progress {
    final totalBytes = this.totalBytes;
    if (totalBytes == null || totalBytes <= 0) {
      return null;
    }
    if (bytesWritten >= totalBytes) {
      return 1.0;
    }
    return bytesWritten / totalBytes;
  }
}

class PickedEntry {
  const PickedEntry({
    required this.path,
    required this.name,
    required this.kind,
    this.relativePath,
    this.metadata = PickedEntryMetadata.empty,
  });

  final String path;
  final String name;
  final PickedEntryKind kind;
  final String? relativePath;
  final PickedEntryMetadata metadata;

  bool get isFile => kind == PickedEntryKind.file;

  bool get isDirectory => kind == PickedEntryKind.directory;

  FilegateLocationKind get locationKind => _locationKindFor(path);

  bool get isUri => locationKind != FilegateLocationKind.platformPath;

  bool get isContentUri => locationKind == FilegateLocationKind.contentUri;

  Uri? get uri => uriForIdentifier(path);

  String? get fileSystemPath => fileSystemPathForIdentifier(path);

  int? get size => metadata.size;

  DateTime? get modifiedAt => metadata.modifiedAt;

  String? get mimeType => metadata.mimeType;

  Map<String, Object?> toMap() {
    return {
      'path': path,
      'name': name,
      'kind': kind.name,
      'relativePath': relativePath,
      'metadata': metadata.toMap(),
    };
  }

  factory PickedEntry.fromMap(Map<Object?, Object?> map) {
    final path = map['path'];
    final name = map['name'];
    final kind = map['kind'];
    final relativePath = map['relativePath'];
    final metadata = map['metadata'];

    if (path is! String ||
        name is! String ||
        kind is! String ||
        (relativePath != null && relativePath is! String) ||
        (metadata != null && metadata is! Map<Object?, Object?>)) {
      throw ArgumentError.value(map, 'map', 'Invalid picked entry payload');
    }

    final decodedMetadata = metadata as Map<Object?, Object?>?;

    return PickedEntry(
      path: path,
      name: name,
      kind: PickedEntryKind.values.byName(kind),
      relativePath: relativePath as String?,
      metadata: decodedMetadata == null
          ? PickedEntryMetadata.empty
          : PickedEntryMetadata.fromMap(decodedMetadata),
    );
  }
}

FilegateLocationKind _locationKindFor(String identifier) {
  final uri = uriForIdentifier(identifier);
  if (uri == null) {
    return FilegateLocationKind.platformPath;
  }

  return switch (uri.scheme.toLowerCase()) {
    'file' => FilegateLocationKind.fileUri,
    'content' => FilegateLocationKind.contentUri,
    _ => FilegateLocationKind.otherUri,
  };
}

DateTime? _decodeModifiedAt(Object? value, Map<Object?, Object?> source) {
  if (value == null) {
    return null;
  }
  if (value is int) {
    return DateTime.fromMillisecondsSinceEpoch(value, isUtc: true);
  }
  if (value is String) {
    final parsed = DateTime.tryParse(value);
    if (parsed != null) {
      return parsed.toUtc();
    }
  }
  throw ArgumentError.value(source, 'map', 'Invalid metadata modifiedAt');
}

class FileReadChunk {
  const FileReadChunk({
    required this.data,
    required this.bytesRead,
    required this.totalBytes,
  });

  final Uint8List data;
  final int bytesRead;
  final int? totalBytes;

  double? get progress {
    final totalBytes = this.totalBytes;
    if (totalBytes == null || totalBytes <= 0) {
      return null;
    }
    if (bytesRead >= totalBytes) {
      return 1.0;
    }
    return bytesRead / totalBytes;
  }
}
