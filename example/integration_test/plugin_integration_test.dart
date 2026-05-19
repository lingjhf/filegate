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
    expect(find.text('Save file'), findsOneWidget);
    expect(find.text('Write file'), findsOneWidget);
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

    await tester.pageBack();
    await _pumpFrames(tester);
    await tester.tap(find.byKey(const ValueKey<String>('save-example-tile')));
    await _pumpFrames(tester);
    expect(
      find.byKey(const ValueKey<String>('save-file-button')),
      findsOneWidget,
    );

    await tester.pageBack();
    await _pumpFrames(tester);
    await tester.tap(find.byKey(const ValueKey<String>('write-example-tile')));
    await _pumpFrames(tester);
    expect(
      find.byKey(const ValueKey<String>('pick-write-target-button')),
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

  testWidgets('save page renders returned file entry', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(MyApp(filegate: _FakeFilegate()));

    await tester.tap(find.byKey(const ValueKey<String>('save-example-tile')));
    await _pumpFrames(tester);
    await tester.tap(find.byKey(const ValueKey<String>('save-file-button')));
    await _pumpFrames(tester);

    expect(find.text('Saved filegate-export.txt'), findsOneWidget);
    expect(find.text('filegate-export.txt'), findsOneWidget);
    expect(
      find.text('/tmp/filegate-export.txt | 16 bytes | text/plain'),
      findsOneWidget,
    );
  });

  testWidgets('write page renders updated file entry', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(MyApp(filegate: _FakeFilegate()));

    await tester.tap(find.byKey(const ValueKey<String>('write-example-tile')));
    await _pumpFrames(tester);
    await tester.tap(
      find.byKey(const ValueKey<String>('pick-write-target-button')),
    );
    await _pumpFrames(tester);
    await tester.tap(find.byKey(const ValueKey<String>('replace-file-button')));
    await _pumpFrames(tester);

    expect(find.text('Replaced notes.txt'), findsOneWidget);
    expect(find.text('notes.txt'), findsOneWidget);
    expect(find.text('/tmp/notes.txt | 21 bytes | text/plain'), findsOneWidget);
  });

  testWidgets('native file APIs read and write a sandbox file', (_) async {
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
    expect(capabilities.supportsFileWriting, isTrue);
    expect(capabilities.supportsFileStreamWriting, isTrue);
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

    final appendBytes = Uint8List.fromList('++'.codeUnits);
    final appended = await filegate.writeFile(
      file.path,
      appendBytes,
      mode: FilegateWriteMode.append,
    );
    expect(appended.name, 'sample.txt');
    expect(appended.fileSystemPath, file.path);
    expect(appended.size, bytes.length + appendBytes.length);
    expect(
      (await file.readAsBytes()).toList(),
      bytes.followedBy(appendBytes).toList(),
    );

    final replaceBytes = Uint8List.fromList('reset\n'.codeUnits);
    final replaced = await filegate.writeFile(file.path, replaceBytes);
    expect(replaced.name, 'sample.txt');
    expect(replaced.fileSystemPath, file.path);
    expect(replaced.size, replaceBytes.length);
    expect((await file.readAsBytes()).toList(), replaceBytes.toList());

    final streamAppendBytes = Uint8List.fromList('stream\n'.codeUnits);
    final streamAppended = await filegate.writeStream(
      file.path,
      Stream<List<int>>.fromIterable([
        streamAppendBytes.sublist(0, 3),
        streamAppendBytes.sublist(3),
      ]),
      mode: FilegateWriteMode.append,
    );
    expect(streamAppended.name, 'sample.txt');
    expect(streamAppended.fileSystemPath, file.path);
    expect(streamAppended.size, replaceBytes.length + streamAppendBytes.length);
    expect(
      (await file.readAsBytes()).toList(),
      replaceBytes.followedBy(streamAppendBytes).toList(),
    );

    final openSessionBytes = Uint8List.fromList('open-session\n'.codeUnits);
    final writeSession = await filegate.openWrite(file.path);
    expect(await file.readAsBytes(), isEmpty);
    await writeSession.add(openSessionBytes.sublist(0, 4));
    await writeSession.add(openSessionBytes.sublist(4));
    final streamed = await writeSession.close();
    expect(streamed.name, 'sample.txt');
    expect(streamed.fileSystemPath, file.path);
    expect(streamed.size, openSessionBytes.length);
    expect((await file.readAsBytes()).toList(), openSessionBytes.toList());

    await expectLater(
      filegate.writeFile(
        '${directory.path}${Platform.pathSeparator}missing.txt',
        replaceBytes,
      ),
      throwsA(
        isA<PlatformException>().having(
          (error) => error.code,
          'code',
          FilegateErrorCode.pathNotFound,
        ),
      ),
    );
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
      supportsFileSaving: true,
      supportsFileWriting: true,
      supportsFileStreamWriting: true,
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

  @override
  Future<PickedEntry?> saveFile(
    Uint8List bytes, {
    required String suggestedName,
    List<String> allowedExtensions = const [],
    String? title,
    String? initialDirectory,
    String? mimeType,
    bool persistAccess = true,
  }) async {
    return PickedEntry(
      path: '/tmp/$suggestedName',
      name: suggestedName,
      kind: PickedEntryKind.file,
      metadata: PickedEntryMetadata(size: bytes.length, mimeType: mimeType),
    );
  }

  @override
  Future<PickedEntry> writeFile(
    String path,
    Uint8List bytes, {
    FilegateWriteMode mode = FilegateWriteMode.replace,
  }) async {
    return PickedEntry(
      path: path,
      name: path.split('/').last,
      kind: PickedEntryKind.file,
      metadata: PickedEntryMetadata(
        size: mode == FilegateWriteMode.append ? 28 : bytes.length,
        mimeType: 'text/plain',
      ),
    );
  }

  @override
  Future<PickedEntry> writeStream(
    String path,
    Stream<List<int>> chunks, {
    FilegateWriteMode mode = FilegateWriteMode.replace,
    int? totalBytes,
    FilegateWriteProgressCallback? onProgress,
  }) async {
    var size = 0;
    await for (final chunk in chunks) {
      if (chunk.isEmpty) {
        continue;
      }
      size += chunk.length;
      onProgress?.call(
        FileWriteProgress(bytesWritten: size, totalBytes: totalBytes),
      );
    }
    return PickedEntry(
      path: path,
      name: path.split('/').last,
      kind: PickedEntryKind.file,
      metadata: PickedEntryMetadata(
        size: mode == FilegateWriteMode.append ? 30 + size : size,
        mimeType: 'text/plain',
      ),
    );
  }
}
