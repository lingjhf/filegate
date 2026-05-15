import 'dart:typed_data';

enum FilegateSelectionMode { filesOnly, directoriesOnly, filesAndDirectories }

enum PickedEntryKind { file, directory }

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
