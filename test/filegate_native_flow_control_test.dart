import 'dart:async';

import 'package:filegate/filegate_method_channel.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const codec = StandardMethodCodec();
  const eventChannel = 'filegate/read/flow-test';
  const channel = MethodChannel('filegate');
  late List<MethodCall> calls;
  late int chunk;

  void emit() {
    messenger.handlePlatformMessage(
      eventChannel,
      chunk < 3
          ? codec.encodeSuccessEnvelope(Uint8List.fromList([++chunk]))
          : null,
      (_) {},
    );
  }

  setUp(() {
    chunk = 0;
    calls = [];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'startRead') return 'flow-test';
      if (call.method == 'ackRead') emit();
      return null;
    });
    messenger.setMockMessageHandler(eventChannel, (message) async {
      final call = codec.decodeMethodCall(message);
      if (call.method == 'listen') emit();
      return codec.encodeSuccessEnvelope(null);
    });
  });
  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
    messenger.setMockMessageHandler(eventChannel, null);
  });

  test('native read acknowledges chunks only after consumer resumes', () async {
    final session = MethodChannelFilegate(
      forceNativeRead: true,
    ).openRead('content://test');
    final first = Completer<void>();
    final done = Completer<void>();
    final bytes = <int>[];
    late StreamSubscription<Uint8List> subscription;
    subscription = session.stream.listen((data) {
      bytes.addAll(data);
      if (!first.isCompleted) {
        subscription.pause();
        first.complete();
      }
    }, onDone: done.complete);
    await first.future;
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(calls.where((call) => call.method == 'ackRead'), isEmpty);
    expect(chunk, 1);
    expect(calls.first.arguments, containsPair('flowControlled', true));
    subscription.resume();
    await done.future;
    expect(bytes, [1, 2, 3]);
    expect(calls.where((call) => call.method == 'ackRead'), hasLength(3));
    await session.cancel();
  });

  test('native cancellation completes while consumer is paused', () async {
    final session = MethodChannelFilegate(
      forceNativeRead: true,
    ).openRead('content://test');
    final first = Completer<void>();
    late StreamSubscription<Uint8List> subscription;
    subscription = session.stream.listen((_) {
      subscription.pause();
      first.complete();
    });
    await first.future;
    await session.cancel().timeout(const Duration(seconds: 1));
    await subscription.cancel();
    expect(calls.where((call) => call.method == 'ackRead'), isEmpty);
    expect(calls.where((call) => call.method == 'cancelRead'), hasLength(1));
  });

  test(
    'native stream paused before startup withholds acknowledgement',
    () async {
      final session = MethodChannelFilegate(
        forceNativeRead: true,
      ).openRead('content://test');
      final bytes = <int>[];
      final done = Completer<void>();
      final subscription = session.stream.listen(
        bytes.addAll,
        onDone: done.complete,
      );
      subscription.pause();
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(bytes, isEmpty);
      expect(calls.where((call) => call.method == 'ackRead'), isEmpty);
      subscription.resume();
      await done.future;
      expect(bytes, [1, 2, 3]);
    },
  );

  test(
    'pausing and cancelling one reader leaves another reader independent',
    () async {
      final positions = <String, int>{'first': 0, 'second': 0};
      void emitFor(String id) {
        final position = positions[id]!;
        positions[id] = position + 1;
        messenger.handlePlatformMessage(
          'filegate/read/$id',
          position < 3
              ? codec.encodeSuccessEnvelope(Uint8List.fromList([position + 1]))
              : null,
          (_) {},
        );
      }

      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        final arguments = call.arguments as Map;
        if (call.method == 'startRead') return arguments['path'];
        if (call.method == 'ackRead') emitFor(arguments['streamId'] as String);
        return null;
      });
      for (final id in positions.keys) {
        final eventName = 'filegate/read/$id';
        messenger.setMockMessageHandler(eventName, (message) async {
          if (codec.decodeMethodCall(message).method == 'listen') emitFor(id);
          return codec.encodeSuccessEnvelope(null);
        });
        addTearDown(() => messenger.setMockMessageHandler(eventName, null));
      }

      final platform = MethodChannelFilegate(forceNativeRead: true);
      final first = platform.openRead('first');
      final receivedFirst = Completer<void>();
      late StreamSubscription<Uint8List> firstSubscription;
      firstSubscription = first.stream.listen((_) {
        firstSubscription.pause();
        receivedFirst.complete();
      });
      await receivedFirst.future;
      final second = platform.openRead('second');
      final secondChunks = await second.stream.toList();
      await second.cancel();
      expect(secondChunks.expand((chunk) => chunk), [1, 2, 3]);
      expect(positions['first'], 1);
      expect(
        calls
            .where((call) => call.method == 'ackRead')
            .map((call) => (call.arguments as Map)['streamId']),
        ['second', 'second', 'second'],
      );

      await first.cancel().timeout(const Duration(seconds: 1));
      await firstSubscription.cancel();
      expect(
        calls
            .where((call) => call.method == 'cancelRead')
            .map((call) => (call.arguments as Map)['streamId']),
        unorderedEquals(['first', 'second']),
      );
    },
  );
}
