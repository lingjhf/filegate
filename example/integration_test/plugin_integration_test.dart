import 'dart:io';

import 'package:filegate/filegate.dart';
import 'package:filegate_example/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('example app starts', (WidgetTester tester) async {
    await tester.pumpWidget(MyApp(filegate: _FakeFilegate()));

    expect(find.text('filegate example'), findsOneWidget);
    expect(find.text('Capabilities'), findsOneWidget);
    expect(find.text('Files'), findsOneWidget);
    expect(find.text('Directory'), findsOneWidget);
    expect(find.text('Read file'), findsOneWidget);
  });

  testWidgets('example pages can be opened from the list', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(MyApp(filegate: _FakeFilegate()));

    await tester.tap(
      find.byKey(const ValueKey<String>('capabilities-example-tile')),
    );
    await _pumpFrames(tester);
    expect(
      find.byKey(const ValueKey<String>('capabilities-list')),
      findsOneWidget,
    );

    await tester.pageBack();
    await _pumpFrames(tester);
    await tester.tap(find.byKey(const ValueKey<String>('files-example-tile')));
    await _pumpFrames(tester);
    expect(
      find.byKey(const ValueKey<String>('pick-files-button')),
      findsOneWidget,
    );

    await tester.pageBack();
    await _pumpFrames(tester);
    await tester.tap(
      find.byKey(const ValueKey<String>('directory-example-tile')),
    );
    await _pumpFrames(tester);
    expect(
      find.byKey(const ValueKey<String>('pick-directory-button')),
      findsOneWidget,
    );

    await tester.pageBack();
    await _pumpFrames(tester);
    await tester.tap(find.byKey(const ValueKey<String>('read-example-tile')));
    await _pumpFrames(tester);
    expect(
      find.byKey(const ValueKey<String>('read-file-button')),
      findsOneWidget,
    );
  });

  testWidgets('example picker actions render returned entries', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(MyApp(filegate: _FakeFilegate()));

    await tester.tap(find.byKey(const ValueKey<String>('files-example-tile')));
    await _pumpFrames(tester);
    await tester.tap(find.byKey(const ValueKey<String>('pick-files-button')));
    await _pumpFrames(tester);
    expect(find.text('2 file(s) selected'), findsOneWidget);
    expect(find.text('notes.txt'), findsOneWidget);
    expect(find.text('/tmp/notes.txt | 6 bytes | text/plain'), findsOneWidget);

    await tester.pageBack();
    await _pumpFrames(tester);
    await tester.tap(
      find.byKey(const ValueKey<String>('directory-example-tile')),
    );
    await _pumpFrames(tester);
    await tester.tap(
      find.byKey(const ValueKey<String>('pick-directory-button')),
    );
    await _pumpFrames(tester);
    expect(find.text('2 file(s) found'), findsOneWidget);
    expect(find.text('README.md'), findsOneWidget);
    expect(
      find.text('/tmp/project/README.md | 10 bytes | text/markdown'),
      findsOneWidget,
    );
  });

  testWidgets('read page previews selected file bytes', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(MyApp(filegate: _FakeFilegate()));

    await tester.tap(find.byKey(const ValueKey<String>('read-example-tile')));
    await _pumpFrames(tester);
    await tester.tap(find.byKey(const ValueKey<String>('read-file-button')));
    await _pumpFrames(tester);

    expect(find.text('Loaded notes.txt'), findsOneWidget);
    expect(find.text('6 bytes'), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('read-preview')), findsOneWidget);
    expect(find.text('66 69 6c 65 21 0a'), findsOneWidget);
  });

  testWidgets('native file APIs read a sandbox file', (_) async {
    final directory = await Directory.systemTemp.createTemp(
      'filegate-integration-',
    );
    addTearDown(() async {
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
    });

    final bytes = Uint8List.fromList(const <int>[
      0x66,
      0x69,
      0x6c,
      0x65,
      0x67,
      0x61,
      0x74,
      0x65,
      0x0a,
    ]);
    final file = File('${directory.path}${Platform.pathSeparator}sample.txt');
    final alphaFile = File(
      '${directory.path}${Platform.pathSeparator}alpha.txt',
    );
    await file.writeAsBytes(bytes, flush: true);
    await alphaFile.writeAsString('alpha', flush: true);
    final pickedFile = PickedEntry(
      path: file.path,
      name: 'sample.txt',
      kind: PickedEntryKind.file,
      metadata: PickedEntryMetadata(size: bytes.length),
    );

    const filegate = Filegate();

    final capabilities = await filegate.getCapabilities();
    final transientPickOptions = const FilegatePickOptions(
      persistAccess: false,
    );
    expect(capabilities.supportsFilePicking, isTrue);
    expect(capabilities.supportsDirectoryPicking, isTrue);
    expect(transientPickOptions.toMap(), containsPair('persistAccess', false));
    expect(pickedFile.locationKind, FilegateLocationKind.platformPath);
    expect(pickedFile.fileSystemPath, file.path);
    expect(pickedFile.size, bytes.length);

    expect(await filegate.getFileSize(file.path), bytes.length);
    await expectLater(
      filegate.getFileSize(directory.path),
      throwsA(
        isA<PlatformException>().having(
          (error) => error.code,
          'code',
          FilegateErrorCode.notAFile,
        ),
      ),
    );

    final allBytes = await filegate.readAllBytes(file.path, chunkSize: 3);
    expect(allBytes.toList(), bytes.toList());

    final rangeBytes = await filegate.readByteRange(
      file.path,
      start: 4,
      length: 4,
      chunkSize: 2,
    );
    expect(rangeBytes.toList(), bytes.skip(4).take(4).toList());

    final listedFiles = await filegate.listDirectoryFiles(directory.path);
    expect(listedFiles, hasLength(2));
    expect(listedFiles.map((entry) => entry.name), const [
      'alpha.txt',
      'sample.txt',
    ]);
    expect(listedFiles.last.size, bytes.length);

    final session = filegate.openRead(file.path, chunkSize: 4, start: 4);
    final chunks = await session.stream.toList();
    expect(chunks.expand((chunk) => chunk).toList(), bytes.skip(4).toList());

    final boundedSession = filegate.openRead(
      file.path,
      chunkSize: 3,
      start: 2,
      end: 7,
    );
    final boundedChunks = await boundedSession.stream.toList();
    expect(
      boundedChunks.expand((chunk) => chunk).toList(),
      bytes.skip(2).take(5).toList(),
    );

    final progressSession = filegate.openReadWithProgress(
      file.path,
      chunkSize: 3,
      start: 2,
      end: 7,
    );
    final progressChunks = await progressSession.stream.toList();
    expect(
      progressChunks.expand((chunk) => chunk.data).toList(),
      bytes.skip(2).take(5).toList(),
    );
    expect(progressChunks.last.bytesRead, 5);
    expect(progressChunks.last.totalBytes, 5);
    expect(progressChunks.last.progress, 1.0);
  });
}

Future<void> _pumpFrames(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
}

class _FakeFilegate extends Filegate {
  @override
  Future<FilegateCapabilities> getCapabilities() async {
    return const FilegateCapabilities(
      supportsFilePicking: true,
      supportsDirectoryPicking: true,
      supportsMixedPicking: false,
      supportsInitialDirectory: true,
      supportsPersistedAccess: true,
      supportsNativeUriRead: false,
    );
  }

  @override
  Future<List<PickedEntry>?> pickFiles({
    bool allowMultiple = false,
    List<String> allowedExtensions = const [],
    String? title,
    String? initialDirectory,
    bool persistAccess = true,
  }) async {
    return const <PickedEntry>[
      PickedEntry(
        path: '/tmp/notes.txt',
        name: 'notes.txt',
        kind: PickedEntryKind.file,
        metadata: PickedEntryMetadata(size: 6, mimeType: 'text/plain'),
      ),
      PickedEntry(
        path: '/tmp/config.json',
        name: 'config.json',
        kind: PickedEntryKind.file,
        metadata: PickedEntryMetadata(size: 2, mimeType: 'application/json'),
      ),
    ];
  }

  @override
  Future<List<PickedEntry>?> pickDirectoryFiles({
    bool recursive = false,
    List<String> allowedExtensions = const [],
    String? title,
    String? initialDirectory,
    bool persistAccess = true,
  }) async {
    return const <PickedEntry>[
      PickedEntry(
        path: '/tmp/project/README.md',
        name: 'README.md',
        kind: PickedEntryKind.file,
        relativePath: 'README.md',
        metadata: PickedEntryMetadata(size: 10, mimeType: 'text/markdown'),
      ),
      PickedEntry(
        path: '/tmp/project/config.json',
        name: 'config.json',
        kind: PickedEntryKind.file,
        relativePath: 'config.json',
        metadata: PickedEntryMetadata(size: 2, mimeType: 'application/json'),
      ),
    ];
  }

  @override
  Future<int?> getFileSize(String path) async => 6;

  @override
  Future<Uint8List> readAllBytes(
    String path, {
    int chunkSize = 64 * 1024,
    int? maxBytes,
  }) async {
    return Uint8List.fromList(const <int>[0x66, 0x69, 0x6c, 0x65, 0x21, 0x0a]);
  }
}
