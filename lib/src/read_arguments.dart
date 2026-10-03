void validateReadArguments(
  String path, {
  required int chunkSize,
  required int start,
  required int? end,
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
  if (end != null && end < start) {
    throw ArgumentError.value(
      end,
      'end',
      'end must be greater than or equal to start',
    );
  }
}
