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
    bool persistAccess = true,
  }) async {
    return const <PickedEntry>[
      PickedEntry(
        path: '/tmp/project/README.md',
        name: 'README.md',
        kind: PickedEntryKind.file,
        relativePath: 'README.md',
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
}
