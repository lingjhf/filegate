import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:filegate/filegate.dart';
import 'package:filegate/filegate_method_channel.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> withReader(
    _TrackingReader reader,
    Future<void> Function(FileReadSession<Uint8List>) body,
  ) {
    return IOOverrides.runZoned(
      () => body(MethodChannelFilegate().openRead('sample.bin', chunkSize: 1)),
      createFile: (_) => _ReadFile(reader),
      fseGetType: (_, _) async => FileSystemEntityType.file,
      fseGetTypeSync: (_, _) => FileSystemEntityType.file,
    );
  }

  test('desktop reader stops producing while the consumer is paused', () async {
    final reader = _TrackingReader();
    await withReader(reader, (session) async {
      final first = Completer<void>();
      late StreamSubscription<Uint8List> subscription;
      subscription = session.stream.listen((_) {
        subscription.pause();
        if (!first.isCompleted) first.complete();
      });
      await first.future;
      await Future<void>.delayed(const Duration(milliseconds: 30));
      final readsWhilePaused = reader.reads;
      subscription.resume();
      await subscription.cancel();
      expect(readsWhilePaused, lessThanOrEqualTo(2));
      expect(reader.closes, 1);
    });
  });

  test('desktop session cancel completes while its stream is paused', () async {
    final reader = _TrackingReader();
    await withReader(reader, (session) async {
      final first = Completer<void>();
      late StreamSubscription<Uint8List> subscription;
      subscription = session.stream.listen((_) {
        if (!first.isCompleted) {
          subscription.pause();
          first.complete();
        }
      });
      await first.future;
      final cancellation = session.cancel();
      var completed = false;
      unawaited(cancellation.then((_) => completed = true));
      await Future<void>.delayed(const Duration(milliseconds: 30));
      final cancelledWhilePaused = completed;
      subscription.resume();
      await subscription.cancel();
      await cancellation;
      expect(cancelledWhilePaused, isTrue);
      expect(reader.closes, 1);
    });
  });

  test(
    'desktop session cancel waits for a pending open and closes it',
    () async {
      final reader = _TrackingReader();
      final opening = Completer<RandomAccessFile>();
      final openStarted = Completer<void>();
      await IOOverrides.runZoned(
        () async {
          final session = MethodChannelFilegate().openRead('sample.bin');
          final subscription = session.stream.listen((_) {});
          await openStarted.future;
          var completed = false;
          final cancellation = session.cancel();
          unawaited(cancellation.then((_) => completed = true));
          await Future<void>.delayed(Duration.zero);
          final returnedBeforeOpen = completed;
          opening.complete(reader);
          await cancellation;
          await subscription.cancel();
          expect(returnedBeforeOpen, isFalse);
          expect(reader.reads, 0);
          expect(reader.closes, 1);
        },
        createFile: (_) => _ReadFile(
          reader,
          onOpen: () {
            openStarted.complete();
            return opening.future;
          },
        ),
        fseGetType: (_, _) async => FileSystemEntityType.file,
        fseGetTypeSync: (_, _) => FileSystemEntityType.file,
      );
    },
  );

  test(
    'desktop reader cancels without closing during an in-flight read',
    () async {
      final reader = _TrackingReader(blockRead: true);
      await withReader(reader, (session) async {
        final subscription = session.stream.listen((_) {});
        await reader.readStarted.future;
        final cancellation = session.cancel();
        await Future<void>.delayed(Duration.zero);
        final closedDuringRead = reader.closes;
        reader.pendingRead.complete(Uint8List.fromList([1]));
        await cancellation;
        await subscription.cancel();
        expect(closedDuringRead, 0);
        expect(reader.closes, 1);
      });
    },
  );

  test('desktop reader accepts encoded file URI identifiers', () async {
    final directory = await Directory.systemTemp.createTemp('filegate-uri-');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}${Platform.pathSeparator}a b.bin');
    await file.writeAsBytes([1, 2, 3]);
    final chunks = await MethodChannelFilegate()
        .openRead(file.uri.toString(), chunkSize: 2)
        .stream
        .toList();
    expect(chunks.expand((chunk) => chunk), [1, 2, 3]);
  });

  test('desktop cancellation before listening never opens a file', () async {
    var opens = 0;
    await IOOverrides.runZoned(
      () async {
        final session = MethodChannelFilegate().openRead('sample.bin');
        await session.cancel();
        await expectLater(session.stream, emitsDone);
        expect(opens, 0);
      },
      createFile: (_) {
        opens++;
        return _ReadFile(_TrackingReader());
      },
    );
  });
}

class _ReadFile implements File {
  _ReadFile(this.reader, {this.onOpen});
  final _TrackingReader reader;
  final Future<RandomAccessFile> Function()? onOpen;

  @override
  Future<RandomAccessFile> open({FileMode mode = FileMode.read}) async =>
      onOpen == null ? reader : await onOpen!();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TrackingReader implements RandomAccessFile {
  _TrackingReader({this.blockRead = false});
  final bool blockRead;
  final readStarted = Completer<void>();
  final pendingRead = Completer<Uint8List>();
  int reads = 0;
  int closes = 0;

  @override
  Future<int> length() async => 100;

  @override
  Future<RandomAccessFile> setPosition(int position) async => this;

  @override
  Future<Uint8List> read(int bytes) async {
    reads++;
    if (!readStarted.isCompleted) readStarted.complete();
    if (blockRead) return pendingRead.future;
    return Uint8List.fromList([reads]);
  }

  @override
  Future<void> close() async {
    closes++;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
