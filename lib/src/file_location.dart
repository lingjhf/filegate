final _windowsDrivePathPattern = RegExp(r'^[A-Za-z]:(?:[\\/]|[^\\/].*)');
final _windowsFileUriPathPattern = RegExp(r'^/[A-Za-z]:(?:/|$)');

Uri? uriForIdentifier(String identifier) {
  if (identifier.isEmpty || _windowsDrivePathPattern.hasMatch(identifier)) {
    return null;
  }

  final uri = Uri.tryParse(identifier);
  if (uri == null || uri.scheme.isEmpty) {
    return null;
  }
  return uri;
}

String? fileSystemPathForIdentifier(String identifier) {
  final uri = uriForIdentifier(identifier);
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

// Plain POSIX file names may contain a colon; only file: identifiers need
// URI decoding when opening a desktop file.
String? desktopReadPath(String identifier) =>
    identifier.toLowerCase().startsWith('file:')
    ? fileSystemPathForIdentifier(identifier)
    : identifier;
