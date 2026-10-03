import 'dart:io';

import 'package:filegate/filegate.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'directory listing uses the same extension normalization as picking',
    () async {
      final root = await Directory.systemTemp.createTemp('filegate-filter-');
      addTearDown(() => root.delete(recursive: true));
      await File(
        '${root.path}${Platform.pathSeparator}video.MP4',
      ).writeAsBytes([1]);
      await File(
        '${root.path}${Platform.pathSeparator}notes.txt',
      ).writeAsBytes([2]);
      const filters = ['  ..MP4  ', ' ...mp4 ', '  '];
      final options = const FilegatePickOptions(
        allowedExtensions: filters,
      ).toMap();
      expect(options['allowedExtensions'], ['mp4']);
      final entries = await const Filegate().listDirectoryFiles(
        root.path,
        allowedExtensions: filters,
      );
      expect(entries.map((entry) => entry.name), ['video.MP4']);
    },
  );
}
