void validateNonEmptyPath(String path, {String argumentName = 'path'}) {
  if (path.isEmpty) {
    throw ArgumentError.value(
      path,
      argumentName,
      '$argumentName must not be empty',
    );
  }
}

void validateFileName(String name, {required String argumentName}) {
  if (name.trim().isEmpty) {
    throw ArgumentError.value(
      name,
      argumentName,
      '$argumentName must not be empty',
    );
  }
  if (name.contains('/') || name.contains(r'\')) {
    throw ArgumentError.value(
      name,
      argumentName,
      '$argumentName must be a file name, not a path',
    );
  }
}

void validateWriteProgressTotalBytes(int? totalBytes) {
  if (totalBytes != null && totalBytes < 0) {
    throw ArgumentError.value(
      totalBytes,
      'totalBytes',
      'totalBytes must not be negative',
    );
  }
}
