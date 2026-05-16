import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:filegate/filegate.dart';
import 'package:filegate/filegate_method_channel.dart';
import 'package:filegate/filegate_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockFilegatePlatform
    with MockPlatformInterfaceMixin
    implements FilegatePlatform {
  FilegatePickOptions? lastOptions;
  int? fileSize = 123;
  List<Uint8List> chunks = <Uint8List>[
    Uint8List.fromList(const [1, 2, 3]),
  ];
  int cancelCount = 0;
  int openReadCount = 0;
  int? lastChunkSize;
  int? lastStart;
  int? lastEnd;
  Object? getFileSizeError;
  FilegateCapabilities capabilities = const FilegateCapabilities(
    supportsFilePicking: true,
    supportsDirectoryPicking: true,
    supportsMixedPicking: false,
    supportsInitialDirectory: true,
    supportsPersistedAccess: true,
    supportsNativeUriRead: true,
  );

  @override
  Future<FilegateCapabilities> getCapabilities() {
    return Future.value(capabilities);
  }

  @override
  Future<List<PickedEntry>?> pick(FilegatePickOptions options) {
    lastOptions = options;
    return Future.value(const [
      PickedEntry(
        path: '/tmp/example.txt',
        name: 'example.txt',
        kind: PickedEntryKind.file,
      ),
    ]);
  }

  @override
  Future<int?> getFileSize(String path) {
    final error = getFileSizeError;
    if (error != null) {
      return Future<int?>.error(error);
    }
    return Future.value(fileSize);
  }

  @override
  FileReadSession<Uint8List> openRead(
    String path, {
    int chunkSize = 64 * 1024,
    int start = 0,
    int? end,
  }) {
    openReadCount += 1;
    lastChunkSize = chunkSize;
    lastStart = start;
    lastEnd = end;
    if (start < 0) {
      throw ArgumentError.value(start, 'start', 'start must not be negative');
    }

    return FileReadSession<Uint8List>(
      stream: Stream<Uint8List>.fromIterable(chunks),
      onCancel: () async {
        cancelCount += 1;
      },
    );
  }
}

void main() {
  final FilegatePlatform initialPlatform = FilegatePlatform.instance;

  tearDown(() {
    FilegatePlatform.instance = initialPlatform;
  });

  test('$MethodChannelFilegate is the default instance', () {
    expect(initialPlatform, isInstanceOf<MethodChannelFilegate>());
  });

  test('pick delegates to the active platform', () async {
    const filegatePlugin = Filegate();
    final fakePlatform = MockFilegatePlatform();
    FilegatePlatform.instance = fakePlatform;

    final result = await filegatePlugin.pick(const FilegatePickOptions());
    expect(result, hasLength(1));
    expect(result!.single.path, '/tmp/example.txt');
    expect(result.single.kind, PickedEntryKind.file);
  });

  test('openRead delegates to the active platform', () async {
    const filegatePlugin = Filegate();
    final fakePlatform = MockFilegatePlatform();
    FilegatePlatform.instance = fakePlatform;

    final chunks = await filegatePlugin
        .openRead('/tmp/example.txt')
        .stream
        .map((chunk) => chunk.toList())
        .toList();

    expect(chunks, const [
      <int>[1, 2, 3],
    ]);
  });

  test('getFileSize delegates to the active platform', () async {
    const filegatePlugin = Filegate();
    final fakePlatform = MockFilegatePlatform();
    FilegatePlatform.instance = fakePlatform;

    final size = await filegatePlugin.getFileSize('/tmp/example.txt');

    expect(size, 123);
  });

  test('getCapabilities delegates to the active platform', () async {
    const filegatePlugin = Filegate();
    final fakePlatform = MockFilegatePlatform();
    FilegatePlatform.instance = fakePlatform;

    final capabilities = await filegatePlugin.getCapabilities();

    expect(capabilities.supportsFilePicking, isTrue);
    expect(capabilities.supportsMixedPicking, isFalse);
    expect(capabilities.supportsNativeUriRead, isTrue);
  });

  test('capabilities round-trip map payloads', () {
    const capabilities = FilegateCapabilities(
      supportsFilePicking: true,
      supportsDirectoryPicking: true,
      supportsMixedPicking: false,
      supportsInitialDirectory: true,
      supportsPersistedAccess: true,
      supportsNativeUriRead: false,
    );

    final restored = FilegateCapabilities.fromMap(capabilities.toMap());

    expect(restored.supportsFilePicking, capabilities.supportsFilePicking);
    expect(
      restored.supportsDirectoryPicking,
      capabilities.supportsDirectoryPicking,
    );
    expect(restored.supportsMixedPicking, capabilities.supportsMixedPicking);
    expect(
      restored.supportsInitialDirectory,
      capabilities.supportsInitialDirectory,
    );
    expect(
      restored.supportsPersistedAccess,
      capabilities.supportsPersistedAccess,
    );
    expect(restored.supportsNativeUriRead, capabilities.supportsNativeUriRead);
  });

  test('capabilities reject invalid payloads', () {
    expect(
      () => FilegateCapabilities.fromMap(const {
        'supportsFilePicking': true,
        'supportsDirectoryPicking': true,
        'supportsMixedPicking': false,
        'supportsInitialDirectory': true,
        'supportsPersistedAccess': true,
        'supportsNativeUriRead': 'false',
      }),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('picked entry round-trips relativePath', () {
    const entry = PickedEntry(
      path: '/tmp/Movie/sub/example.txt',
      name: 'example.txt',
      kind: PickedEntryKind.file,
      relativePath: 'Movie/sub/example.txt',
    );

    final restored = PickedEntry.fromMap(entry.toMap());

    expect(restored.path, entry.path);
    expect(restored.name, entry.name);
    expect(restored.kind, entry.kind);
    expect(restored.relativePath, entry.relativePath);
    expect(restored.isFile, isTrue);
    expect(restored.isDirectory, isFalse);
  });

  test('picked entry classifies platform paths', () {
    const posixEntry = PickedEntry(
      path: '/tmp/example.txt',
      name: 'example.txt',
      kind: PickedEntryKind.file,
    );
    const windowsEntry = PickedEntry(
      path: r'C:\tmp\example.txt',
      name: 'example.txt',
      kind: PickedEntryKind.file,
    );
    const windowsDriveRelativeEntry = PickedEntry(
      path: r'C:tmp\example.txt',
      name: 'example.txt',
      kind: PickedEntryKind.file,
    );

    expect(posixEntry.locationKind, FilegateLocationKind.platformPath);
    expect(posixEntry.isUri, isFalse);
    expect(posixEntry.uri, isNull);
    expect(posixEntry.fileSystemPath, '/tmp/example.txt');
    expect(windowsEntry.locationKind, FilegateLocationKind.platformPath);
    expect(windowsEntry.fileSystemPath, r'C:\tmp\example.txt');
    expect(
      windowsDriveRelativeEntry.locationKind,
      FilegateLocationKind.platformPath,
    );
    expect(windowsDriveRelativeEntry.fileSystemPath, r'C:tmp\example.txt');
  });

  test('picked entry exposes file URI paths', () {
    const posixEntry = PickedEntry(
      path: 'file:///tmp/example.txt',
      name: 'example.txt',
      kind: PickedEntryKind.file,
    );
    const windowsEntry = PickedEntry(
      path: 'file:///C:/Users/example.txt',
      name: 'example.txt',
      kind: PickedEntryKind.file,
    );

    expect(posixEntry.locationKind, FilegateLocationKind.fileUri);
    expect(posixEntry.isUri, isTrue);
    expect(posixEntry.uri!.scheme, 'file');
    expect(posixEntry.fileSystemPath, '/tmp/example.txt');
    expect(windowsEntry.fileSystemPath, r'C:\Users\example.txt');
  });

  test('picked entry classifies non-file URIs', () {
    const contentEntry = PickedEntry(
      path: 'content://com.example.provider/document/1',
      name: 'example.txt',
      kind: PickedEntryKind.file,
    );
    const customEntry = PickedEntry(
      path: 'filegate://example/item',
      name: 'example.txt',
      kind: PickedEntryKind.file,
    );

    expect(contentEntry.locationKind, FilegateLocationKind.contentUri);
    expect(contentEntry.isContentUri, isTrue);
    expect(contentEntry.uri!.scheme, 'content');
    expect(contentEntry.fileSystemPath, isNull);
    expect(customEntry.locationKind, FilegateLocationKind.otherUri);
    expect(customEntry.fileSystemPath, isNull);
  });

  test('picked entry round-trips metadata', () {
    final modifiedAt = DateTime.utc(2026, 5, 16, 1, 2, 3);
    final entry = PickedEntry(
      path: '/tmp/example.txt',
      name: 'example.txt',
      kind: PickedEntryKind.file,
      metadata: PickedEntryMetadata(
        size: 42,
        modifiedAt: modifiedAt,
        mimeType: 'text/plain',
      ),
    );

    final restored = PickedEntry.fromMap(entry.toMap());

    expect(restored.metadata.isNotEmpty, isTrue);
    expect(restored.size, 42);
    expect(restored.modifiedAt, modifiedAt);
    expect(restored.mimeType, 'text/plain');
  });

  test('picked entry decodes ISO metadata timestamps', () {
    final entry = PickedEntry.fromMap(const {
      'path': '/tmp/example.txt',
      'name': 'example.txt',
      'kind': 'file',
      'metadata': {'modifiedAt': '2026-05-16T01:02:03Z'},
    });

    expect(entry.modifiedAt, DateTime.utc(2026, 5, 16, 1, 2, 3));
  });

  test('picked entry rejects invalid metadata payloads', () {
    expect(
      () => PickedEntry.fromMap(const {
        'path': '/tmp/example.txt',
        'name': 'example.txt',
        'kind': 'file',
        'metadata': {'size': -1},
      }),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('directory picked entry round-trips kind', () {
    const entry = PickedEntry(
      path: '/tmp/Movie',
      name: 'Movie',
      kind: PickedEntryKind.directory,
      relativePath: 'Movie',
    );

    final restored = PickedEntry.fromMap(entry.toMap());

    expect(restored.path, entry.path);
    expect(restored.name, entry.name);
    expect(restored.kind, PickedEntryKind.directory);
    expect(restored.relativePath, entry.relativePath);
    expect(restored.isFile, isFalse);
    expect(restored.isDirectory, isTrue);
  });

  test('picked entry rejects invalid native payloads', () {
    expect(
      () => PickedEntry.fromMap(const {
        'path': '/tmp/example.txt',
        'name': 'example.txt',
        'kind': 1,
      }),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('error code constants include stable API contract values', () {
    expect(FilegateErrorCode.invalidArgs, 'invalid_args');
    expect(FilegateErrorCode.unsupportedMode, 'unsupported_mode');
    expect(FilegateErrorCode.noActivity, 'no_activity');
    expect(FilegateErrorCode.noViewController, 'no_view_controller');
    expect(FilegateErrorCode.pickerActive, 'picker_active');
    expect(FilegateErrorCode.pathNotFound, 'path_not_found');
    expect(FilegateErrorCode.notAFile, 'not_a_file');
    expect(FilegateErrorCode.notADirectory, 'not_a_directory');
    expect(FilegateErrorCode.permissionDenied, 'permission_denied');
    expect(
      FilegateErrorCode.persistPermissionFailed,
      'persist_permission_failed',
    );
    expect(FilegateErrorCode.securityScopeFailed, 'security_scope_failed');
    expect(FilegateErrorCode.pickFailed, 'pick_failed');
    expect(FilegateErrorCode.pickerFailed, 'picker_failed');
    expect(FilegateErrorCode.streamActive, 'stream_active');
    expect(FilegateErrorCode.missingStreamId, 'missing_stream_id');
    expect(FilegateErrorCode.invalidChunk, 'invalid_chunk');
    expect(FilegateErrorCode.readOpenFailed, 'read_open_failed');
    expect(FilegateErrorCode.readFailed, 'read_failed');
    expect(FilegateErrorCode.enumerationFailed, 'enumeration_failed');
  });

  test('openReadWithProgress wraps chunks with cumulative progress', () async {
    const filegatePlugin = Filegate();
    final fakePlatform = MockFilegatePlatform();
    FilegatePlatform.instance = fakePlatform;

    final events = await filegatePlugin
        .openReadWithProgress('/tmp/example.txt')
        .stream
        .toList();

    expect(events, hasLength(1));
    expect(events.single.bytesRead, 3);
    expect(events.single.totalBytes, 123);
    expect(events.single.data, Uint8List.fromList(const [1, 2, 3]));
    expect(events.single.progress, closeTo(3 / 123, 0.0001));
  });

  test('openReadWithProgress accumulates multiple chunks', () async {
    const filegatePlugin = Filegate();
    final fakePlatform = MockFilegatePlatform()
      ..fileSize = 5
      ..chunks = <Uint8List>[
        Uint8List.fromList(const [1, 2]),
        Uint8List.fromList(const [3, 4, 5]),
      ];
    FilegatePlatform.instance = fakePlatform;

    final events = await filegatePlugin
        .openReadWithProgress('/tmp/example.txt')
        .stream
        .toList();

    expect(events, hasLength(2));
    expect(events.first.bytesRead, 2);
    expect(events.first.progress, closeTo(0.4, 0.0001));
    expect(events.last.bytesRead, 5);
    expect(events.last.progress, closeTo(1.0, 0.0001));
  });

  test('openReadWithProgress uses ranged totals', () async {
    const filegatePlugin = Filegate();
    final fakePlatform = MockFilegatePlatform()
      ..fileSize = 10
      ..chunks = <Uint8List>[
        Uint8List.fromList(const [1, 2, 3]),
      ];
    FilegatePlatform.instance = fakePlatform;

    final events = await filegatePlugin
        .openReadWithProgress('/tmp/example.txt', start: 2, end: 5)
        .stream
        .toList();

    expect(events.single.totalBytes, 3);
    expect(events.single.progress, 1.0);
    expect(fakePlatform.lastStart, 2);
    expect(fakePlatform.lastEnd, 5);
  });

  test(
    'openReadWithProgress keeps null progress when file size is unknown',
    () async {
      const filegatePlugin = Filegate();
      final fakePlatform = MockFilegatePlatform()..fileSize = null;
      FilegatePlatform.instance = fakePlatform;

      final events = await filegatePlugin
          .openReadWithProgress('/tmp/example.txt')
          .stream
          .toList();

      expect(events.single.totalBytes, isNull);
      expect(events.single.progress, isNull);
    },
  );

  test('openReadWithProgress continues when getFileSize throws', () async {
    const filegatePlugin = Filegate();
    final fakePlatform = MockFilegatePlatform()
      ..getFileSizeError = PlatformException(
        code: FilegateErrorCode.permissionDenied,
        message: 'The provided path is not readable.',
      );
    FilegatePlatform.instance = fakePlatform;

    final events = await filegatePlugin
        .openReadWithProgress('/tmp/example.txt')
        .stream
        .toList();

    expect(events, hasLength(1));
    expect(events.single.totalBytes, isNull);
    expect(events.single.progress, isNull);
    expect(events.single.data, Uint8List.fromList(const [1, 2, 3]));
  });

  test(
    'openReadWithProgress continues when getFileSize throws non-platform errors',
    () async {
      const filegatePlugin = Filegate();
      final fakePlatform = MockFilegatePlatform()
        ..getFileSizeError = StateError('size unavailable');
      FilegatePlatform.instance = fakePlatform;

      final events = await filegatePlugin
          .openReadWithProgress('/tmp/example.txt')
          .stream
          .toList();

      expect(events, hasLength(1));
      expect(events.single.totalBytes, isNull);
      expect(events.single.progress, isNull);
    },
  );

  test('file read chunk progress is capped at complete', () {
    final chunk = FileReadChunk(
      data: Uint8List.fromList(const [1, 2, 3]),
      bytesRead: 3,
      totalBytes: 2,
    );

    expect(chunk.progress, 1.0);
  });

  test('pick options normalize recursive and extensions', () {
    const options = FilegatePickOptions(
      recursive: true,
      allowedExtensions: [' .TXT ', 'yaml', '.yaml', '.', ''],
      persistAccess: false,
    );

    expect(options.toMap()['recursive'], true);
    expect(options.toMap()['allowedExtensions'], const ['txt', 'yaml']);
    expect(options.toMap()['persistAccess'], false);
  });

  test('pickFiles builds file-only options', () async {
    const filegatePlugin = Filegate();
    final fakePlatform = MockFilegatePlatform();
    FilegatePlatform.instance = fakePlatform;

    await filegatePlugin.pickFiles(
      allowMultiple: true,
      allowedExtensions: const ['txt'],
      title: 'Pick files',
      persistAccess: false,
    );

    expect(
      fakePlatform.lastOptions!.selectionMode,
      FilegateSelectionMode.filesOnly,
    );
    expect(fakePlatform.lastOptions!.allowMultiple, true);
    expect(fakePlatform.lastOptions!.allowedExtensions, const ['txt']);
    expect(fakePlatform.lastOptions!.persistAccess, false);
  });

  test('pickDirectoryFiles builds directory-only options', () async {
    const filegatePlugin = Filegate();
    final fakePlatform = MockFilegatePlatform();
    FilegatePlatform.instance = fakePlatform;

    await filegatePlugin.pickDirectoryFiles(
      recursive: true,
      persistAccess: false,
    );

    expect(
      fakePlatform.lastOptions!.selectionMode,
      FilegateSelectionMode.directoriesOnly,
    );
    expect(fakePlatform.lastOptions!.recursive, true);
    expect(fakePlatform.lastOptions!.persistAccess, false);
  });

  test('pickMixed builds mixed options', () async {
    const filegatePlugin = Filegate();
    final fakePlatform = MockFilegatePlatform();
    FilegatePlatform.instance = fakePlatform;

    await filegatePlugin.pickMixed(
      allowMultiple: true,
      recursive: true,
      persistAccess: false,
    );

    expect(
      fakePlatform.lastOptions!.selectionMode,
      FilegateSelectionMode.filesAndDirectories,
    );
    expect(fakePlatform.lastOptions!.allowMultiple, true);
    expect(fakePlatform.lastOptions!.recursive, true);
    expect(fakePlatform.lastOptions!.persistAccess, false);
  });

  test('readAllBytes aggregates all chunks', () async {
    const filegatePlugin = Filegate();
    final fakePlatform = MockFilegatePlatform();
    FilegatePlatform.instance = fakePlatform;

    final data = await filegatePlugin.readAllBytes('/tmp/example.txt');

    expect(data, Uint8List.fromList(const [1, 2, 3]));
  });

  test('readAllBytes enforces maxBytes and cancels the session', () async {
    const filegatePlugin = Filegate();
    final fakePlatform = MockFilegatePlatform()
      ..chunks = <Uint8List>[
        Uint8List.fromList(const [1, 2]),
        Uint8List.fromList(const [3, 4]),
      ];
    FilegatePlatform.instance = fakePlatform;

    await expectLater(
      () => filegatePlugin.readAllBytes('/tmp/example.txt', maxBytes: 3),
      throwsA(isA<StateError>()),
    );
    expect(fakePlatform.cancelCount, 1);
  });

  test(
    'readAllBytes rejects negative maxBytes without opening a stream',
    () async {
      const filegatePlugin = Filegate();
      final fakePlatform = MockFilegatePlatform();
      FilegatePlatform.instance = fakePlatform;

      await expectLater(
        () => filegatePlugin.readAllBytes('/tmp/example.txt', maxBytes: -1),
        throwsA(isA<ArgumentError>()),
      );
      expect(fakePlatform.openReadCount, 0);
    },
  );

  test(
    'readByteRange reads an exact range without explicit cancellation',
    () async {
      const filegatePlugin = Filegate();
      final fakePlatform = MockFilegatePlatform()
        ..chunks = <Uint8List>[
          Uint8List.fromList(const [1, 2, 3]),
          Uint8List.fromList(const [4, 5, 6]),
        ];
      FilegatePlatform.instance = fakePlatform;

      final data = await filegatePlugin.readByteRange(
        '/tmp/example.txt',
        start: 2,
        length: 5,
        chunkSize: 4,
      );

      expect(data.toList(), const [1, 2, 3, 4, 5]);
      expect(fakePlatform.lastStart, 2);
      expect(fakePlatform.lastEnd, 7);
      expect(fakePlatform.lastChunkSize, 4);
      expect(fakePlatform.cancelCount, 0);
    },
  );

  test('readByteRange clamps chunk size to requested length', () async {
    const filegatePlugin = Filegate();
    final fakePlatform = MockFilegatePlatform();
    FilegatePlatform.instance = fakePlatform;

    await filegatePlugin.readByteRange(
      '/tmp/example.txt',
      start: 0,
      length: 2,
      chunkSize: 64,
    );

    expect(fakePlatform.lastChunkSize, 2);
  });

  test(
    'readByteRange returns empty bytes without opening zero-length ranges',
    () async {
      const filegatePlugin = Filegate();
      final fakePlatform = MockFilegatePlatform();
      FilegatePlatform.instance = fakePlatform;

      final data = await filegatePlugin.readByteRange(
        '/tmp/example.txt',
        start: 10,
        length: 0,
      );

      expect(data, isEmpty);
      expect(fakePlatform.openReadCount, 0);
    },
  );

  test('readByteRange validates range arguments', () {
    const filegatePlugin = Filegate();

    expect(
      () => filegatePlugin.readByteRange(
        '/tmp/example.txt',
        start: -1,
        length: 1,
      ),
      throwsA(isA<ArgumentError>()),
    );
    expect(
      () => filegatePlugin.readByteRange(
        '/tmp/example.txt',
        start: 0,
        length: -1,
      ),
      throwsA(isA<ArgumentError>()),
    );
    expect(
      () => filegatePlugin.readByteRange(
        '/tmp/example.txt',
        start: 0,
        length: 1,
        chunkSize: 0,
      ),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('listDirectoryFiles enumerates files with metadata', () async {
    final root = await Directory.systemTemp.createTemp('filegate-list-');
    addTearDown(() async {
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    });
    final nested = Directory('${root.path}${Platform.pathSeparator}nested');
    await nested.create();
    final readme = File('${root.path}${Platform.pathSeparator}README.md');
    final notes = File('${nested.path}${Platform.pathSeparator}notes.TXT');
    final zeta = File('${root.path}${Platform.pathSeparator}zeta.txt');
    await readme.writeAsString('readme');
    await notes.writeAsString('notes');
    await zeta.writeAsString('zeta');

    const filegatePlugin = Filegate();
    final entries = await filegatePlugin.listDirectoryFiles(
      root.path,
      recursive: true,
      allowedExtensions: const ['txt'],
    );

    expect(entries, hasLength(2));
    expect(entries.map((entry) => entry.relativePath), const [
      'nested/notes.TXT',
      'zeta.txt',
    ]);
    expect(entries.first.name, 'notes.TXT');
    expect(entries.first.size, 5);
    expect(entries.first.modifiedAt, isNotNull);
  });

  test('listDirectoryFiles reports missing and non-directory paths', () async {
    final root = await Directory.systemTemp.createTemp('filegate-list-');
    addTearDown(() async {
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    });
    final file = File('${root.path}${Platform.pathSeparator}sample.txt');
    await file.writeAsString('sample');

    await expectLater(
      const Filegate().listDirectoryFiles(
        '${root.path}${Platform.pathSeparator}missing',
      ),
      throwsA(
        isA<PlatformException>().having(
          (error) => error.code,
          'code',
          FilegateErrorCode.pathNotFound,
        ),
      ),
    );
    await expectLater(
      const Filegate().listDirectoryFiles(file.path),
      throwsA(
        isA<PlatformException>().having(
          (error) => error.code,
          'code',
          FilegateErrorCode.notADirectory,
        ),
      ),
    );
  });

  test('listDirectoryFiles rejects empty directory paths', () {
    expect(
      () => const Filegate().listDirectoryFiles(''),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('openRead rejects negative start offsets', () {
    const filegatePlugin = Filegate();
    final fakePlatform = MockFilegatePlatform();
    FilegatePlatform.instance = fakePlatform;

    expect(
      () => filegatePlugin.openRead('/tmp/example.txt', start: -1),
      throwsA(isA<ArgumentError>()),
    );
    expect(fakePlatform.openReadCount, 0);
  });

  test('openRead validates public read arguments before platform calls', () {
    const filegatePlugin = Filegate();
    final fakePlatform = MockFilegatePlatform();
    FilegatePlatform.instance = fakePlatform;

    expect(() => filegatePlugin.openRead(''), throwsA(isA<ArgumentError>()));
    expect(
      () => filegatePlugin.openRead('/tmp/example.txt', chunkSize: 0),
      throwsA(isA<ArgumentError>()),
    );
    expect(
      () => filegatePlugin.openRead('/tmp/example.txt', start: 2, end: 1),
      throwsA(isA<ArgumentError>()),
    );
    expect(fakePlatform.openReadCount, 0);
  });

  test('openRead allows EOF offsets and returns an empty stream', () async {
    const filegatePlugin = Filegate();
    final fakePlatform = MockFilegatePlatform()..chunks = const <Uint8List>[];
    FilegatePlatform.instance = fakePlatform;

    final chunks = await filegatePlugin
        .openRead('/tmp/example.txt', start: 3)
        .stream
        .toList();

    expect(chunks, isEmpty);
  });

  test('file read session cancel is idempotent', () async {
    var cancelCount = 0;
    final session = FileReadSession<int>(
      stream: const Stream<int>.empty(),
      onCancel: () async {
        cancelCount += 1;
      },
    );

    await session.cancel();
    await session.cancel();

    expect(cancelCount, 1);
  });
}
