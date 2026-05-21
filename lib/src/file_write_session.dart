import 'dart:async';
import 'dart:typed_data';

import 'models.dart';

class FileWriteSession {
  FileWriteSession({
    required this._onAdd,
    required this._onClose,
    required this._onCancel,
    this._totalBytes,
    this._onProgress,
  });

  final Future<void> Function(Uint8List chunk) _onAdd;
  final Future<PickedEntry> Function() _onClose;
  final Future<void> Function() _onCancel;
  final int? _totalBytes;
  final FilegateWriteProgressCallback? _onProgress;

  Future<void> _tail = Future<void>.value();
  bool _closeRequested = false;
  bool _cancelRequested = false;
  bool _closed = false;
  int _bytesWritten = 0;
  Future<PickedEntry>? _closeFuture;
  Future<void>? _cancelFuture;

  Future<void> add(List<int> chunk) {
    if (_closeRequested) {
      return Future<void>.error(StateError('Cannot add after close().'));
    }
    if (_cancelRequested) {
      return Future<void>.error(StateError('Cannot add after cancel().'));
    }

    final bytes = Uint8List.fromList(chunk);
    return _tail = _tail.then((_) {
      if (_cancelRequested) {
        throw StateError('Cannot add after cancel().');
      }
      if (bytes.isEmpty) {
        return Future<void>.value();
      }
      return _onAdd(bytes).then((_) {
        _bytesWritten += bytes.length;
        _onProgress?.call(
          FileWriteProgress(
            bytesWritten: _bytesWritten,
            totalBytes: _totalBytes,
          ),
        );
      });
    });
  }

  Future<void> addStream(Stream<List<int>> chunks) async {
    await for (final chunk in chunks) {
      await add(chunk);
    }
  }

  Future<PickedEntry> close() {
    if (_cancelRequested) {
      return Future<PickedEntry>.error(
        StateError('Cannot close after cancel().'),
      );
    }
    _closeRequested = true;
    return _closeFuture ??= _tail.then((_) async {
      final entry = await _onClose();
      _closed = true;
      return entry;
    });
  }

  Future<void> cancel() {
    if (_closed) {
      return Future<void>.value();
    }
    _cancelRequested = true;
    return _cancelFuture ??= _onCancel();
  }
}
