import 'dart:async';

class FileReadSession<T> {
  FileReadSession({required this.stream, required this._onCancel});

  final Stream<T> stream;
  final Future<void> Function() _onCancel;

  bool _cancelled = false;
  Future<void>? _cancelFuture;

  Future<void> cancel() {
    if (_cancelled) {
      return _cancelFuture ?? Future.value();
    }
    _cancelled = true;
    return _cancelFuture = _onCancel();
  }
}
