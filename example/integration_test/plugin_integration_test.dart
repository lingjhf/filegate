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
    expect(find.text('Files'), findsOneWidget);
    expect(find.text('Directory'), findsOneWidget);
    expect(find.text('Read file'), findsOneWidget);
  });

  testWidgets('example pages can be opened from the list', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(MyApp(filegate: _FakeFilegate()));

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
  });

  testWidgets('example picker actions render returned entries', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(MyApp(filegate: _FakeFilegate()));

    await tester.tap(find.byKey(const ValueKey<String>('files-example-tile')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('pick-files-button')));
    await tester.pumpAndSettle();
    expect(find.text('2 file(s) selected'), findsOneWidget);
    expect(find.text('notes.txt'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('directory-example-tile')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('pick-directory-button')),
    );
    await tester.pumpAndSettle();
    expect(find.text('2 file(s) found'), findsOneWidget);
    expect(find.text('project/README.md'), findsOneWidget);
  });

  testWidgets('read page previews selected file bytes', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(MyApp(filegate: _FakeFilegate()));

    await tester.tap(find.byKey(const ValueKey<String>('read-example-tile')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('read-file-button')));
    await tester.pumpAndSettle();

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
    await file.writeAsBytes(bytes, flush: true);
    final pickedFile = PickedEntry(
      path: file.path,
      name: 'sample.txt',
      kind: PickedEntryKind.file,
    );

    const filegate = Filegate();

    final capabilities = await filegate.getCapabilities();
    expect(capabilities.supportsFilePicking, isTrue);
    expect(capabilities.supportsDirectoryPicking, isTrue);
    expect(pickedFile.locationKind, FilegateLocationKind.platformPath);
    expect(pickedFile.fileSystemPath, file.path);

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

    final session = filegate.openRead(file.path, chunkSize: 4, start: 4);
    final chunks = await session.stream.toList();
    expect(chunks.expand((chunk) => chunk).toList(), bytes.skip(4).toList());
  });
}

class _FakeFilegate extends Filegate {
  @override
  Future<List<PickedEntry>?> pickFiles({
    bool allowMultiple = false,
    List<String> allowedExtensions = const [],
    String? title,
    String? initialDirectory,
  }) async {
    return const <PickedEntry>[
      PickedEntry(
        path: '/tmp/notes.txt',
        name: 'notes.txt',
        kind: PickedEntryKind.file,
      ),
      PickedEntry(
        path: '/tmp/config.json',
        name: 'config.json',
        kind: PickedEntryKind.file,
      ),
    ];
  }

  @override
  Future<List<PickedEntry>?> pickDirectoryFiles({
    bool recursive = false,
    List<String> allowedExtensions = const [],
    String? title,
    String? initialDirectory,
  }) async {
    return const <PickedEntry>[
      PickedEntry(
        path: '/tmp/project/README.md',
        name: 'README.md',
        kind: PickedEntryKind.file,
        relativePath: 'project/README.md',
      ),
      PickedEntry(
        path: '/tmp/project/config.json',
        name: 'config.json',
        kind: PickedEntryKind.file,
        relativePath: 'project/config.json',
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
