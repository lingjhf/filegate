import 'dart:typed_data';

import 'package:filegate/filegate.dart';
import 'package:filegate_example/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('example app renders and opens each page', (tester) async {
    await tester.pumpWidget(MyApp(filegate: _FakeFilegate()));

    expect(find.text('filegate example'), findsOneWidget);
    expect(find.text('Capabilities'), findsOneWidget);
    expect(find.text('Files'), findsOneWidget);
    expect(find.text('Directory'), findsOneWidget);
    expect(find.text('Read file'), findsOneWidget);
    expect(find.text('Save file'), findsOneWidget);
    expect(find.text('Write file'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey<String>('capabilities-example-tile')),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('capabilities-list')),
      findsOneWidget,
    );
    expect(find.text('File picking'), findsOneWidget);
    expect(find.text('Native URI read'), findsOneWidget);
    expect(find.text('File saving'), findsOneWidget);
    expect(find.text('File writing'), findsOneWidget);
    expect(find.text('Stream writing'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('files-example-tile')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('pick-files-button')),
      findsOneWidget,
    );

    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('directory-example-tile')),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('pick-directory-button')),
      findsOneWidget,
    );

    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('read-example-tile')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('read-file-button')),
      findsOneWidget,
    );

    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('save-example-tile')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('save-file-button')),
      findsOneWidget,
    );

    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('write-example-tile')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('pick-write-target-button')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('stream-write-button')),
      findsOneWidget,
    );
  });

  testWidgets('file picker page displays selected files', (tester) async {
    await tester.pumpWidget(MyApp(filegate: _FakeFilegate()));

    await tester.tap(find.byKey(const ValueKey<String>('files-example-tile')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('pick-files-button')));
    await tester.pumpAndSettle();

    expect(find.text('2 file(s) selected'), findsOneWidget);
    expect(find.text('notes.txt'), findsOneWidget);
    expect(find.text('config.json'), findsOneWidget);
    expect(find.text('/tmp/notes.txt | 6 bytes | text/plain'), findsOneWidget);
  });

  testWidgets('save page displays saved file result', (tester) async {
    await tester.pumpWidget(MyApp(filegate: _FakeFilegate()));

    await tester.tap(find.byKey(const ValueKey<String>('save-example-tile')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('save-file-button')));
    await tester.pumpAndSettle();

    expect(find.text('Saved filegate-export.txt'), findsOneWidget);
    expect(find.text('filegate-export.txt'), findsOneWidget);
    expect(
      find.text('/tmp/filegate-export.txt | 16 bytes | text/plain'),
      findsOneWidget,
    );
  });

  testWidgets('write page appends to selected file', (tester) async {
    await tester.pumpWidget(MyApp(filegate: _FakeFilegate()));

    await tester.tap(find.byKey(const ValueKey<String>('write-example-tile')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('pick-write-target-button')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('append-file-button')));
    await tester.pumpAndSettle();

    expect(find.text('Appended to notes.txt'), findsOneWidget);
    expect(find.text('notes.txt'), findsOneWidget);
    expect(find.textContaining('/tmp/notes.txt'), findsOneWidget);
  });

  testWidgets('write page streams chunks to selected file', (tester) async {
    await tester.pumpWidget(MyApp(filegate: _FakeFilegate()));

    await tester.tap(find.byKey(const ValueKey<String>('write-example-tile')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('pick-write-target-button')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('stream-write-button')));
    await tester.pumpAndSettle();

    expect(find.text('Streamed chunks to notes.txt'), findsOneWidget);
    expect(find.text('notes.txt'), findsOneWidget);
    expect(find.textContaining('/tmp/notes.txt'), findsOneWidget);
  });
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
    ];
  }

  @override
  Future<int?> getFileSize(String path) async => 4;

  @override
  Future<Uint8List> readAllBytes(
    String path, {
    int chunkSize = 64 * 1024,
    int? maxBytes,
  }) async {
    return Uint8List.fromList(const <int>[1, 2, 3, 4]);
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
