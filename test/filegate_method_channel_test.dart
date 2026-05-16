import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:filegate/filegate_method_channel.dart';
import 'package:filegate/filegate.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final MethodChannelFilegate platform = MethodChannelFilegate(
    forceNativeRead: true,
  );
  final MethodChannelFilegate desktopPlatform = MethodChannelFilegate();
  const MethodChannel channel = MethodChannel('filegate');
  final List<MethodCall> methodCalls = <MethodCall>[];
  Object? pickResponse;
  String startReadResponse = 'stream-1';
  Object? eventPayload = Uint8List.fromList(const [1, 2, 3]);
  PlatformException? getFileSizeError;
  PlatformException? startReadError;
  bool cancelReadThrows = false;

  setUp(() {
    methodCalls.clear();
    pickResponse = [
      {
        'path': '/tmp/example.txt',
        'name': 'example.txt',
        'kind': 'file',
        'relativePath': 'nested/example.txt',
        'metadata': {
          'size': 12,
          'modifiedAt': 1778893200000,
          'mimeType': 'text/plain',
        },
      },
    ];
    startReadResponse = 'stream-1';
    eventPayload = Uint8List.fromList(const [1, 2, 3]);
    getFileSizeError = null;
    startReadError = null;
    cancelReadThrows = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
          methodCalls.add(methodCall);
          if (methodCall.method == 'pick') {
            return pickResponse;
          }

          if (methodCall.method == 'getFileSize') {
            if (getFileSizeError != null) {
              throw getFileSizeError!;
            }
            return 123;
          }

          if (methodCall.method == 'startRead') {
            if (startReadError != null) {
              throw startReadError!;
            }
            return startReadResponse;
          }

          if (methodCall.method == 'cancelRead') {
            if (cancelReadThrows) {
              throw PlatformException(code: 'cancel_failed');
            }
            return null;
          }

          return null;
        });

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler('filegate/read/stream-1', (message) async {
          final codec = const StandardMethodCodec();
          final methodCall = codec.decodeMethodCall(message);
          if (methodCall.method == 'listen') {
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
                .handlePlatformMessage(
                  'filegate/read/stream-1',
                  codec.encodeSuccessEnvelope(eventPayload),
                  (_) {},
                );
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
                .handlePlatformMessage('filegate/read/stream-1', null, (_) {});
          }
          return codec.encodeSuccessEnvelope(null);
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler('filegate/read/stream-1', null);
  });

  test('pick decodes native entries', () async {
    final result = await platform.pick(
      const FilegatePickOptions(
        allowedExtensions: ['.txt'],
        persistAccess: false,
      ),
    );

    expect(result, hasLength(1));
    expect(result!.single.name, 'example.txt');
    expect(result.single.kind, PickedEntryKind.file);
    expect(result.single.relativePath, 'nested/example.txt');
    expect(result.single.size, 12);
    expect(result.single.modifiedAt, DateTime.utc(2026, 5, 16, 1));
    expect(result.single.mimeType, 'text/plain');
    expect(
      methodCalls.firstWhere((call) => call.method == 'pick').arguments,
      containsPair('persistAccess', false),
    );
    expect(
      methodCalls.firstWhere((call) => call.method == 'pick').arguments,
      containsPair('allowedExtensions', const ['txt']),
    );
  });

  test('pick deduplicates entries and sorts them by stable path', () async {
    pickResponse = [
      {
        'path': '/tmp/zeta.txt',
        'name': 'zeta.txt',
        'kind': 'file',
        'relativePath': 'zeta.txt',
      },
      {
        'path': '/tmp/alpha.txt',
        'name': 'alpha.txt',
        'kind': 'file',
        'relativePath': 'alpha.txt',
      },
      {
        'path': '/tmp/zeta.txt',
        'name': 'ignored.txt',
        'kind': 'file',
        'relativePath': 'ignored.txt',
      },
      {
        'path': '/tmp/beta.txt',
        'name': 'beta.txt',
        'kind': 'file',
        'relativePath': 'nested/beta.txt',
      },
    ];

    final result = await platform.pick(const FilegatePickOptions());

    expect(result, hasLength(3));
    expect(result!.map((entry) => entry.path), const [
      '/tmp/alpha.txt',
      '/tmp/beta.txt',
      '/tmp/zeta.txt',
    ]);
    expect(result.map((entry) => entry.relativePath), const [
      'alpha.txt',
      'nested/beta.txt',
      'zeta.txt',
    ]);
  });

  test('capabilities describe Android SAF limits', () {
    final capabilities = MethodChannelFilegate.capabilitiesForOperatingSystem(
      'android',
    );

    expect(capabilities.supportsFilePicking, isTrue);
    expect(capabilities.supportsDirectoryPicking, isTrue);
    expect(capabilities.supportsMixedPicking, isFalse);
    expect(capabilities.supportsPersistedAccess, isTrue);
    expect(capabilities.supportsNativeUriRead, isTrue);
  });

  test('capabilities describe Apple mixed picker support', () {
    final iosCapabilities =
        MethodChannelFilegate.capabilitiesForOperatingSystem('ios');
    final macosCapabilities =
        MethodChannelFilegate.capabilitiesForOperatingSystem('macos');

    expect(iosCapabilities.supportsMixedPicking, isTrue);
    expect(iosCapabilities.supportsNativeUriRead, isTrue);
    expect(macosCapabilities.supportsMixedPicking, isTrue);
    expect(macosCapabilities.supportsNativeUriRead, isFalse);
  });

  test('capabilities describe desktop picker limits', () {
    final windowsCapabilities =
        MethodChannelFilegate.capabilitiesForOperatingSystem('windows');
    final linuxCapabilities =
        MethodChannelFilegate.capabilitiesForOperatingSystem('linux');

    expect(windowsCapabilities.supportsMixedPicking, isFalse);
    expect(windowsCapabilities.supportsPersistedAccess, isTrue);
    expect(linuxCapabilities.supportsMixedPicking, isFalse);
    expect(linuxCapabilities.supportsPersistedAccess, isTrue);
  });

  test('capabilities are disabled for unknown operating systems', () {
    final capabilities = MethodChannelFilegate.capabilitiesForOperatingSystem(
      'unknown',
    );

    expect(capabilities.supportsFilePicking, isFalse);
    expect(capabilities.supportsDirectoryPicking, isFalse);
    expect(capabilities.supportsMixedPicking, isFalse);
    expect(capabilities.supportsInitialDirectory, isFalse);
    expect(capabilities.supportsPersistedAccess, isFalse);
    expect(capabilities.supportsNativeUriRead, isFalse);
  });

  test('pick rejects invalid native entry payloads', () async {
    pickResponse = ['unexpected'];

    await expectLater(
      platform.pick(const FilegatePickOptions()),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('getFileSize validates arguments before touching the channel', () async {
    await expectLater(platform.getFileSize(''), throwsA(isA<ArgumentError>()));
    expect(methodCalls.where((call) => call.method == 'getFileSize'), isEmpty);
  });

  test('openRead validates arguments before touching the channel', () {
    expect(
      () => platform.openRead('', chunkSize: 1),
      throwsA(isA<ArgumentError>()),
    );
    expect(
      () => platform.openRead('/tmp/example.txt', chunkSize: 0),
      throwsA(isA<ArgumentError>()),
    );
    expect(
      () => platform.openRead('/tmp/example.txt', start: -1),
      throwsA(isA<ArgumentError>()),
    );
    expect(
      () => platform.openRead('/tmp/example.txt', start: 2, end: 1),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('openRead returns a cancellable session', () async {
    final session = platform.openRead('/tmp/example.txt');
    final chunks = await session.stream.map((chunk) => chunk.toList()).toList();
    await session.cancel();
    await session.cancel();

    expect(chunks, const [
      <int>[1, 2, 3],
    ]);
    expect(methodCalls.any((call) => call.method == 'startRead'), isTrue);
    expect(methodCalls.where((call) => call.method == 'cancelRead').length, 1);
    expect(
      methodCalls.firstWhere((call) => call.method == 'startRead').arguments,
      containsPair('start', 0),
    );
  });

  test('openRead delivers done to stream listeners', () async {
    final session = platform.openRead('/tmp/example.txt');
    final done = Completer<void>();
    final chunks = <List<int>>[];

    session.stream.listen(
      (chunk) => chunks.add(chunk.toList()),
      onDone: () => done.complete(),
      onError: done.completeError,
    );

    await done.future.timeout(const Duration(seconds: 1));

    expect(chunks, const [
      <int>[1, 2, 3],
    ]);
  });

  test('openRead forwards custom range offsets', () async {
    final session = platform.openRead('/tmp/example.txt', start: 123, end: 456);
    await session.stream.drain<void>();

    final arguments = methodCalls
        .firstWhere((call) => call.method == 'startRead')
        .arguments;
    expect(arguments, containsPair('start', 123));
    expect(arguments, containsPair('end', 456));
  });

  test('openRead with custom start remains cancellable', () async {
    final session = platform.openRead('/tmp/example.txt', start: 123);
    final subscription = session.stream.listen((_) {});
    await Future<void>.delayed(Duration.zero);
    await session.cancel();
    await session.cancel();
    await subscription.cancel();

    expect(
      methodCalls.firstWhere((call) => call.method == 'startRead').arguments,
      containsPair('start', 123),
    );
    expect(
      methodCalls.where((call) => call.method == 'cancelRead'),
      hasLength(1),
    );
  });

  test(
    'openRead fails when native startRead returns empty stream id',
    () async {
      startReadResponse = '';

      final session = platform.openRead('/tmp/example.txt');

      await expectLater(
        session.stream.drain<void>(),
        throwsA(
          isA<PlatformException>().having(
            (error) => error.code,
            'code',
            FilegateErrorCode.missingStreamId,
          ),
        ),
      );
    },
  );

  test('openRead surfaces invalid native chunk types', () async {
    eventPayload = 'unexpected';

    final session = platform.openRead('/tmp/example.txt');

    await expectLater(
      session.stream.drain<void>(),
      throwsA(
        isA<PlatformException>().having(
          (error) => error.code,
          'code',
          FilegateErrorCode.invalidChunk,
        ),
      ),
    );
    expect(
      methodCalls.where((call) => call.method == 'cancelRead'),
      hasLength(1),
    );

    await session.cancel();
    expect(
      methodCalls.where((call) => call.method == 'cancelRead'),
      hasLength(1),
    );
  });

  test('openRead accepts native list chunks', () async {
    eventPayload = const <int>[4, 5, 6];

    final session = platform.openRead('/tmp/example.txt');
    final chunks = await session.stream.map((chunk) => chunk.toList()).toList();

    expect(chunks, const [
      <int>[4, 5, 6],
    ]);
  });

  test('getFileSize decodes native values', () async {
    expect(await platform.getFileSize('/tmp/example.txt'), 123);
  });

  test('getFileSize surfaces native platform exceptions', () async {
    getFileSizeError = PlatformException(
      code: 'not_a_file',
      message: 'The provided path is a directory, not a file.',
    );

    await expectLater(
      platform.getFileSize('/tmp/example.txt'),
      throwsA(
        isA<PlatformException>().having(
          (error) => error.code,
          'code',
          'not_a_file',
        ),
      ),
    );
  });

  test('openRead surfaces native startRead platform exceptions', () async {
    startReadError = PlatformException(
      code: 'permission_denied',
      message: 'The provided path is not readable.',
    );

    final session = platform.openRead('/tmp/example.txt');

    await expectLater(
      session.stream.drain<void>(),
      throwsA(
        isA<PlatformException>().having(
          (error) => error.code,
          'code',
          'permission_denied',
        ),
      ),
    );
  });

  test('cancel ignores native cancellation failures', () async {
    cancelReadThrows = true;

    final session = platform.openRead('/tmp/example.txt');
    await session.stream.drain<void>();

    await expectLater(session.cancel(), completes);
  });

  test('openRead reports desktop directory paths as not_a_file', () async {
    final directory = Directory.systemTemp.createTempSync('filegate-test-');
    addTearDown(() {
      directory.deleteSync(recursive: true);
    });

    final session = desktopPlatform.openRead(directory.path);

    await expectLater(
      session.stream.drain<void>(),
      throwsA(
        isA<PlatformException>().having(
          (error) => error.code,
          'code',
          'not_a_file',
        ),
      ),
    );
    expect(methodCalls.where((call) => call.method == 'startRead'), isEmpty);
  });

  test(
    'openRead reads desktop file paths without native channel calls',
    () async {
      final directory = Directory.systemTemp.createTempSync('filegate-test-');
      addTearDown(() {
        directory.deleteSync(recursive: true);
      });
      final file = File('${directory.path}${Platform.pathSeparator}sample.bin')
        ..writeAsBytesSync(const [1, 2, 3, 4, 5]);

      final session = desktopPlatform.openRead(
        file.path,
        chunkSize: 2,
        start: 1,
      );
      final chunks = await session.stream
          .map((chunk) => chunk.toList())
          .toList();

      expect(chunks, const [
        <int>[2, 3],
        <int>[4, 5],
      ]);
      expect(methodCalls.where((call) => call.method == 'startRead'), isEmpty);
    },
  );

  test('openRead stops desktop streams at exclusive end offsets', () async {
    final directory = Directory.systemTemp.createTempSync('filegate-test-');
    addTearDown(() {
      directory.deleteSync(recursive: true);
    });
    final file = File('${directory.path}${Platform.pathSeparator}sample.bin')
      ..writeAsBytesSync(const [1, 2, 3, 4, 5, 6]);

    final session = desktopPlatform.openRead(
      file.path,
      chunkSize: 4,
      start: 1,
      end: 5,
    );
    final chunks = await session.stream.map((chunk) => chunk.toList()).toList();

    expect(chunks, const [
      <int>[2, 3, 4, 5],
    ]);
    expect(methodCalls.where((call) => call.method == 'startRead'), isEmpty);
  });

  test('openRead returns empty desktop stream past EOF', () async {
    final directory = Directory.systemTemp.createTempSync('filegate-test-');
    addTearDown(() {
      directory.deleteSync(recursive: true);
    });
    final file = File('${directory.path}${Platform.pathSeparator}sample.bin')
      ..writeAsBytesSync(const [1, 2, 3]);

    final session = desktopPlatform.openRead(file.path, chunkSize: 2, start: 4);

    await expectLater(session.stream, emitsDone);
    expect(methodCalls.where((call) => call.method == 'startRead'), isEmpty);
  });

  test('openRead reports missing desktop paths as path_not_found', () async {
    final path =
        '${Directory.systemTemp.path}/filegate-missing-${DateTime.now().microsecondsSinceEpoch}';

    final session = desktopPlatform.openRead(path);

    await expectLater(
      session.stream.drain<void>(),
      throwsA(
        isA<PlatformException>().having(
          (error) => error.code,
          'code',
          'path_not_found',
        ),
      ),
    );
    expect(methodCalls.where((call) => call.method == 'startRead'), isEmpty);
  });
}
