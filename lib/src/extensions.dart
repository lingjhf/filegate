final _leadingDots = RegExp(r'^\.+');

Set<String> normalizeExtensions(Iterable<String> extensions) {
  return extensions
      .map(
        (extension) =>
            extension.trim().replaceFirst(_leadingDots, '').toLowerCase(),
      )
      .where((extension) => extension.isNotEmpty)
      .toSet();
}
