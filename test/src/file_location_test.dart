import 'package:filegate/filegate.dart';
import 'package:filegate/src/file_location.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('desktop file URI decoding agrees with entry location metadata', () {
    for (final identifier in [
      'file:///tmp/a%20b/%E4%B8%AD.bin',
      'file:///C:/a%20b/output.bin',
      'file://server/share/a%20b.bin',
    ]) {
      final entry = PickedEntry(
        path: identifier,
        name: 'output.bin',
        kind: PickedEntryKind.file,
      );
      expect(desktopReadPath(identifier), entry.fileSystemPath);
      expect(desktopReadPath(identifier), isNot(contains('%20')));
    }
  });

  test('plain desktop paths retain colon and percent characters', () {
    for (final path in [
      'scene:take%20.bin',
      '/tmp/scene:take.bin',
      r'C:\a%20b.bin',
    ]) {
      expect(desktopReadPath(path), path);
    }
  });

  test('invalid local file URI cannot be opened as a literal path', () {
    expect(desktopReadPath('file:///tmp/output.bin?query=value'), isNull);
  });
}
