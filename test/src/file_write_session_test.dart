import 'dart:async';

import 'package:filegate/filegate.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'cancel waits for an active chunk before releasing the writer',
    () async {
      final started = Completer<void>();
      final pending = Completer<void>();
      var cancelled = false;
      final session = FileWriteSession(
        onAdd: (_) {
          started.complete();
          return pending.future;
        },
        onClose: () async => throw StateError('Unexpected close'),
        onCancel: () async {
          cancelled = true;
        },
      );
      final write = session.add([1]);
      await started.future;
      final cancel = session.cancel();
      await Future<void>.delayed(Duration.zero);
      final cancelledDuringWrite = cancelled;
      pending.complete();
      await write;
      await cancel;
      expect(cancelledDuringWrite, isFalse);
      expect(cancelled, isTrue);
    },
  );

  test('cancel waits for a pending finish and closes only once', () async {
    final started = Completer<void>();
    final finished = Completer<PickedEntry>();
    var cancels = 0;
    final session = FileWriteSession(
      onAdd: (_) async {},
      onClose: () {
        started.complete();
        return finished.future;
      },
      onCancel: () async {
        cancels++;
      },
    );
    final close = session.close();
    await started.future;
    final cancel = session.cancel();
    await Future<void>.delayed(Duration.zero);
    finished.complete(
      const PickedEntry(path: 'file', name: 'file', kind: PickedEntryKind.file),
    );
    await close;
    await cancel;
    expect(cancels, 0);
  });
}
