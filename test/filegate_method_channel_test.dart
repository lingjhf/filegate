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
  String startReadResponse = 'stream-1';
  Object? eventPayload = Uint8List.fromList(const [1, 2, 3]);
  PlatformException? getFileSizeError;
  PlatformException? startReadError;

  setUp(() {
    methodCalls.clear();
    startReadResponse = 'stream-1';
    eventPayload = Uint8List.fromList(const [1, 2, 3]);
    getFileSizeError = null;
    startReadError = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
          methodCalls.add(methodCall);
          if (methodCall.method == 'pick') {
            return [
              {
                'path': '/tmp/example.txt',
                'name': 'example.txt',
                'kind': 'file',
              },
            ];
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
      const FilegatePickOptions(allowedExtensions: ['.txt']),
    );

    expect(result, hasLength(1));
    expect(result!.single.name, 'example.txt');
    expect(result.single.kind, PickedEntryKind.file);
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

  test('openRead forwards custom start offsets', () async {
    final session = platform.openRead('/tmp/example.txt', start: 123);
    await session.stream.drain<void>();

    expect(
      methodCalls.firstWhere((call) => call.method == 'startRead').arguments,
      containsPair('start', 123),
    );
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
        throwsA(isA<PlatformException>()),
      );
    },
  );

  test('openRead surfaces invalid native chunk types', () async {
    eventPayload = 'unexpected';

    final session = platform.openRead('/tmp/example.txt');

    await expectLater(
      session.stream.drain<void>(),
      throwsA(isA<PlatformException>()),
    );
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
