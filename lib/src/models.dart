import 'dart:typed_data';

enum FilegateSelectionMode { filesOnly, directoriesOnly, filesAndDirectories }

enum PickedEntryKind { file, directory }

enum FilegateLocationKind { platformPath, fileUri, contentUri, otherUri }

class FilegateCapabilities {
  const FilegateCapabilities({
    required this.supportsFilePicking,
    required this.supportsDirectoryPicking,
    required this.supportsMixedPicking,
    required this.supportsInitialDirectory,
    required this.supportsPersistedAccess,
    required this.supportsNativeUriRead,
  });

  final bool supportsFilePicking;
  final bool supportsDirectoryPicking;
  final bool supportsMixedPicking;
  final bool supportsInitialDirectory;
  final bool supportsPersistedAccess;
  final bool supportsNativeUriRead;

  Map<String, Object?> toMap() {
    return {
      'supportsFilePicking': supportsFilePicking,
      'supportsDirectoryPicking': supportsDirectoryPicking,
      'supportsMixedPicking': supportsMixedPicking,
      'supportsInitialDirectory': supportsInitialDirectory,
      'supportsPersistedAccess': supportsPersistedAccess,
      'supportsNativeUriRead': supportsNativeUriRead,
    };
  }

  factory FilegateCapabilities.fromMap(Map<Object?, Object?> map) {
    final supportsFilePicking = map['supportsFilePicking'];
    final supportsDirectoryPicking = map['supportsDirectoryPicking'];
    final supportsMixedPicking = map['supportsMixedPicking'];
    final supportsInitialDirectory = map['supportsInitialDirectory'];
    final supportsPersistedAccess = map['supportsPersistedAccess'];
    final supportsNativeUriRead = map['supportsNativeUriRead'];

    if (supportsFilePicking is! bool ||
        supportsDirectoryPicking is! bool ||
        supportsMixedPicking is! bool ||
        supportsInitialDirectory is! bool ||
        supportsPersistedAccess is! bool ||
        supportsNativeUriRead is! bool) {
      throw ArgumentError.value(map, 'map', 'Invalid capabilities payload');
    }

    return FilegateCapabilities(
      supportsFilePicking: supportsFilePicking,
      supportsDirectoryPicking: supportsDirectoryPicking,
      supportsMixedPicking: supportsMixedPicking,
      supportsInitialDirectory: supportsInitialDirectory,
      supportsPersistedAccess: supportsPersistedAccess,
      supportsNativeUriRead: supportsNativeUriRead,
    );
  }
}

class FilegatePickOptions {
  const FilegatePickOptions({
    this.selectionMode = FilegateSelectionMode.filesOnly,
    this.allowMultiple = false,
    this.allowedExtensions = const [],
    this.recursive = false,
    this.title,
    this.initialDirectory,
  });

  final FilegateSelectionMode selectionMode;
  final bool allowMultiple;
  final List<String> allowedExtensions;
  final bool recursive;
  final String? title;
  final String? initialDirectory;

  Map<String, Object?> toMap() {
    return {
      'selectionMode': selectionMode.name,
      'allowMultiple': allowMultiple,
      'recursive': recursive,
      'allowedExtensions': allowedExtensions
          .map(_normalizeExtension)
          .where((extension) => extension.isNotEmpty)
          .toList(growable: false),
      'title': title,
      'initialDirectory': initialDirectory,
    };
  }

  static String _normalizeExtension(String extension) {
    return extension.startsWith('.') ? extension.substring(1) : extension;
  }
}

class PickedEntry {
  const PickedEntry({
    required this.path,
    required this.name,
    required this.kind,
    this.relativePath,
  });

  final String path;
  final String name;
  final PickedEntryKind kind;
  final String? relativePath;

  bool get isFile => kind == PickedEntryKind.file;

  bool get isDirectory => kind == PickedEntryKind.directory;

  FilegateLocationKind get locationKind => _locationKindFor(path);

  bool get isUri => locationKind != FilegateLocationKind.platformPath;

  bool get isContentUri => locationKind == FilegateLocationKind.contentUri;

  Uri? get uri => _uriFor(path);

  String? get fileSystemPath => _fileSystemPathFor(path);

  Map<String, Object?> toMap() {
    return {
      'path': path,
      'name': name,
      'kind': kind.name,
      'relativePath': relativePath,
    };
  }

  factory PickedEntry.fromMap(Map<Object?, Object?> map) {
    final path = map['path'];
    final name = map['name'];
    final kind = map['kind'];
    final relativePath = map['relativePath'];

    if (path is! String ||
        name is! String ||
        kind is! String ||
        (relativePath != null && relativePath is! String)) {
      throw ArgumentError.value(map, 'map', 'Invalid picked entry payload');
    }

    return PickedEntry(
      path: path,
      name: name,
      kind: PickedEntryKind.values.byName(kind),
      relativePath: relativePath as String?,
    );
  }
}

final _windowsDrivePathPattern = RegExp(r'^[A-Za-z]:(?:[\\/]|[^\\/].*)');
final _windowsFileUriPathPattern = RegExp(r'^/[A-Za-z]:(?:/|$)');

FilegateLocationKind _locationKindFor(String identifier) {
  final uri = _uriFor(identifier);
  if (uri == null) {
    return FilegateLocationKind.platformPath;
  }

  return switch (uri.scheme.toLowerCase()) {
    'file' => FilegateLocationKind.fileUri,
    'content' => FilegateLocationKind.contentUri,
    _ => FilegateLocationKind.otherUri,
  };
}

Uri? _uriFor(String identifier) {
  if (identifier.isEmpty || _windowsDrivePathPattern.hasMatch(identifier)) {
    return null;
  }

  final uri = Uri.tryParse(identifier);
  if (uri == null || uri.scheme.isEmpty) {
    return null;
  }
  return uri;
}

String? _fileSystemPathFor(String identifier) {
  final uri = _uriFor(identifier);
  if (uri == null) {
    return identifier;
  }
  if (uri.scheme.toLowerCase() != 'file') {
    return null;
  }

  try {
    return uri.toFilePath(windows: _shouldDecodeAsWindowsFileUri(uri));
  } on Object {
    return null;
  }
}

bool _shouldDecodeAsWindowsFileUri(Uri uri) {
  return _windowsFileUriPathPattern.hasMatch(uri.path) ||
      (uri.host.isNotEmpty && uri.host.toLowerCase() != 'localhost');
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
    return bytesRead / totalBytes;
  }
}
