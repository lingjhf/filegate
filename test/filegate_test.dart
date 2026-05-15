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
  }) {
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

  test('error code constants include native picker failures', () {
    expect(FilegateErrorCode.pickFailed, 'pick_failed');
    expect(FilegateErrorCode.pickerFailed, 'picker_failed');
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

  test('pick options normalize recursive and extensions', () {
    const options = FilegatePickOptions(
      recursive: true,
      allowedExtensions: ['.txt', 'yaml'],
    );

    expect(options.toMap()['recursive'], true);
    expect(options.toMap()['allowedExtensions'], const ['txt', 'yaml']);
  });

  test('pickFiles builds file-only options', () async {
    const filegatePlugin = Filegate();
    final fakePlatform = MockFilegatePlatform();
    FilegatePlatform.instance = fakePlatform;

    await filegatePlugin.pickFiles(
      allowMultiple: true,
      allowedExtensions: const ['txt'],
      title: 'Pick files',
    );

    expect(
      fakePlatform.lastOptions!.selectionMode,
      FilegateSelectionMode.filesOnly,
    );
    expect(fakePlatform.lastOptions!.allowMultiple, true);
    expect(fakePlatform.lastOptions!.allowedExtensions, const ['txt']);
  });

  test('pickDirectoryFiles builds directory-only options', () async {
    const filegatePlugin = Filegate();
    final fakePlatform = MockFilegatePlatform();
    FilegatePlatform.instance = fakePlatform;

    await filegatePlugin.pickDirectoryFiles(recursive: true);

    expect(
      fakePlatform.lastOptions!.selectionMode,
      FilegateSelectionMode.directoriesOnly,
    );
    expect(fakePlatform.lastOptions!.recursive, true);
  });

  test('pickMixed builds mixed options', () async {
    const filegatePlugin = Filegate();
    final fakePlatform = MockFilegatePlatform();
    FilegatePlatform.instance = fakePlatform;

    await filegatePlugin.pickMixed(allowMultiple: true, recursive: true);

    expect(
      fakePlatform.lastOptions!.selectionMode,
      FilegateSelectionMode.filesAndDirectories,
    );
    expect(fakePlatform.lastOptions!.allowMultiple, true);
    expect(fakePlatform.lastOptions!.recursive, true);
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

  test('openRead rejects negative start offsets', () {
    const filegatePlugin = Filegate();

    expect(
      () => filegatePlugin.openRead('/tmp/example.txt', start: -1),
      throwsA(isA<ArgumentError>()),
    );
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
