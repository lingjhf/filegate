import 'dart:async';
import 'dart:typed_data';

import 'package:filegate/filegate.dart';
import 'package:filegate/filegate_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';

const _entry = PickedEntry(
  path: '/test/output.bin',
  name: 'output.bin',
  kind: PickedEntryKind.file,
);

void main() {
  late FilegatePlatform original;
  setUp(() => original = FilegatePlatform.instance);
  tearDown(() => FilegatePlatform.instance = original);

  test(
    'progress preserves the platform session and snapshots queued chunks',
    () async {
      final chunks = <Uint8List>[];
      final callbacks = <String>[];
      final baseProgress = <FileWriteProgress>[];
      final publicProgress = <FileWriteProgress>[];
      final platformSession = _TrackingSession(
        onAdd: (chunk) async => chunks.add(chunk),
        onClose: () async => _entry,
        onCancel: () async {},
        totalBytes: 100,
        onProgress: (progress) {
          baseProgress.add(progress);
          callbacks.add('platform:${progress.bytesWritten}');
        },
      );
      FilegatePlatform.instance = _WritePlatform(platformSession);
      final session = await const Filegate().openWrite(
        _entry.path,
        totalBytes: 5,
        onProgress: (progress) {
          publicProgress.add(progress);
          callbacks.add('public:${progress.bytesWritten}');
        },
      );

      expect(session, same(platformSession));
      final producerChunk = Uint8List.fromList([1, 2]);
      final firstWrite = session.add(producerChunk);
      producerChunk.fillRange(0, producerChunk.length, 9);
      final emptyWrite = session.add([]);
      final secondWrite = session.add([3, 4, 5]);
      expect(await session.close(), same(_entry));
      await Future.wait([firstWrite, emptyWrite, secondWrite]);

      expect(platformSession.inputs.first, same(producerChunk));
      expect(chunks.first, isNot(same(producerChunk)));
      expect(chunks, [
        [1, 2],
        [3, 4, 5],
      ]);
      expect(callbacks, ['platform:2', 'public:2', 'platform:5', 'public:5']);
      expect(baseProgress.map((progress) => progress.totalBytes), [100, 100]);
      expect(publicProgress.map((progress) => progress.totalBytes), [5, 5]);
      expect(publicProgress.last.progress, 1);
    },
  );

  test(
    'progress cancellation waits for the active write and cancels once',
    () async {
      final started = Completer<void>();
      final release = Completer<void>();
      var cancelCount = 0;
      final progress = <FileWriteProgress>[];
      FilegatePlatform.instance = _WritePlatform(
        FileWriteSession(
          onAdd: (_) async {
            started.complete();
            await release.future;
          },
          onClose: () async => _entry,
          onCancel: () async => cancelCount++,
        ),
      );
      final session = await const Filegate().openWrite(
        _entry.path,
        onProgress: progress.add,
      );
      final write = session.add([1, 2]);
      await started.future;
      final cancellation = session.cancel();
      final repeatedCancellation = session.cancel();
      expect(cancelCount, 0);
      release.complete();
      await Future.wait([write, cancellation, repeatedCancellation]);
      expect(cancelCount, 1);
      expect(progress.single.bytesWritten, 2);
      expect(progress.single.totalBytes, isNull);
      await expectLater(session.add([3]), throwsStateError);
    },
  );

  test(
    'a failed progress callback preserves failure and permits cleanup',
    () async {
      var cancelCount = 0;
      var closeCount = 0;
      final failure = StateError('progress failed');
      FilegatePlatform.instance = _WritePlatform(
        FileWriteSession(
          onAdd: (_) async {},
          onClose: () async {
            closeCount++;
            return _entry;
          },
          onCancel: () async => cancelCount++,
        ),
      );
      final session = await const Filegate().openWrite(
        _entry.path,
        onProgress: (_) => throw failure,
      );
      await expectLater(session.add([1]), throwsA(same(failure)));
      await expectLater(session.close(), throwsA(same(failure)));
      await session.cancel();
      expect(cancelCount, 1);
      expect(closeCount, 0);
    },
  );
}

class _WritePlatform extends FilegatePlatform {
  _WritePlatform(this.session);
  final FileWriteSession session;

  @override
  Future<FileWriteSession> openWrite(
    String path, {
    FilegateWriteMode mode = FilegateWriteMode.replace,
  }) async => session;
}

class _TrackingSession extends FileWriteSession {
  _TrackingSession({
    required super.onAdd,
    required super.onClose,
    required super.onCancel,
    super.totalBytes,
    super.onProgress,
  });
  final inputs = <List<int>>[];

  @override
  Future<void> add(List<int> chunk) {
    inputs.add(chunk);
    return super.add(chunk);
  }
}
