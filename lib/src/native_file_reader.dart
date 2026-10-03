import 'dart:async';

import 'package:flutter/services.dart';

import 'errors.dart';
import 'file_read_session.dart';

class NativeFileReader {
  NativeFileReader({
    required this.channel,
    required this.path,
    required this.chunkSize,
    required this.start,
    required this.end,
  }) {
    _controller = StreamController<Uint8List>(
      onListen: _start,
      onPause: () => _subscription?.pause(),
      onResume: _resume,
      onCancel: cancel,
    );
    session = FileReadSession(stream: _controller.stream, onCancel: cancel);
  }

  static const _readChannelPrefix = 'filegate/read';
  final MethodChannel channel;
  final String path;
  final int chunkSize;
  final int start;
  final int? end;
  late final FileReadSession<Uint8List> session;
  late final StreamController<Uint8List> _controller;
  StreamSubscription<dynamic>? _subscription;
  String? _streamId;
  Future<String?>? _startFuture;
  bool _cancelled = false;
  bool _closed = false;
  bool _awaitingAcknowledgement = false;
  Future<void>? _cancelFuture;
  Future<void>? _nativeCancelFuture;

  Future<void> _start() async {
    try {
      _startFuture = channel.invokeMethod<String>('startRead', {
        'path': path,
        'chunkSize': chunkSize,
        'start': start,
        'end': end,
        'flowControlled': true,
      });
      _streamId = await _startFuture;
      if (_streamId == null || _streamId!.isEmpty) {
        throw PlatformException(
          code: FilegateErrorCode.missingStreamId,
          message: 'Native reader did not return a stream identifier.',
        );
      }
      if (_cancelled) {
        await _cancelStartedRead();
        return;
      }

      _subscription = EventChannel('$_readChannelPrefix/$_streamId')
          .receiveBroadcastStream()
          .listen(_receive, onError: _fail, onDone: _finish);
      if (_controller.isPaused) _subscription?.pause();
    } catch (error, stackTrace) {
      if (!_cancelled) _controller.addError(error, stackTrace);
      _finish();
    }
  }

  void _receive(dynamic event) {
    if (_cancelled || _closed) return;
    if (event is Uint8List) {
      _addChunk(event);
    } else if (event is ByteData) {
      _addChunk(
        event.buffer.asUint8List(event.offsetInBytes, event.lengthInBytes),
      );
    } else if (event is List && event.every((dynamic item) => item is int)) {
      _addChunk(Uint8List.fromList(event.cast<int>()));
    } else {
      _fail(
        PlatformException(
          code: FilegateErrorCode.invalidChunk,
          message: 'Unexpected native chunk type: ${event.runtimeType}.',
        ),
        StackTrace.current,
      );
    }
  }

  void _addChunk(Uint8List chunk) {
    _controller.add(chunk);
    _awaitingAcknowledgement = true;
    // Delivery and consumers pausing the stream must run before acknowledgement.
    scheduleMicrotask(_acknowledgeChunk);
  }

  void _resume() {
    _subscription?.resume();
    scheduleMicrotask(_acknowledgeChunk);
  }

  void _acknowledgeChunk() {
    if (!_awaitingAcknowledgement ||
        _controller.isPaused ||
        _cancelled ||
        _closed) {
      return;
    }
    _awaitingAcknowledgement = false;
    unawaited(() async {
      try {
        await channel.invokeMethod<void>('ackRead', {'streamId': _streamId});
      } catch (error, stackTrace) {
        _fail(error, stackTrace);
      }
    }());
  }

  void _fail(Object error, StackTrace stackTrace) {
    if (_cancelled || _closed) return;
    _controller.addError(error, stackTrace);
    unawaited(cancel());
  }

  void _finish() {
    if (_closed) return;
    _closed = true;
    // Cleanup must not wait for a paused consumer to observe completion.
    unawaited(_controller.close());
  }

  Future<void> cancel() {
    return _cancelFuture ??= () async {
      _cancelled = true;
      await _cancelSubscription();
      await _cancelStartedRead();
      _finish();
    }();
  }

  Future<void> _cancelSubscription() async {
    try {
      await _subscription?.cancel();
    } on MissingPluginException {
      // The dynamic event channel may already have been released.
    } on PlatformException {
      // The native stream may have ended before Dart observes teardown.
    }
  }

  Future<void> _cancelStartedRead() async {
    final activeId = _streamId;
    if (activeId != null && activeId.isNotEmpty) {
      await (_nativeCancelFuture ??= _cancelNative(activeId));
      return;
    }
    final pendingStart = _startFuture;
    if (pendingStart == null) return;
    try {
      final pendingId = await pendingStart;
      if (pendingId != null && pendingId.isNotEmpty) {
        await (_nativeCancelFuture ??= _cancelNative(pendingId));
      }
    } on Object {
      // A failed startRead has no native stream to cancel.
    }
  }

  Future<void> _cancelNative(String streamId) async {
    try {
      await channel.invokeMethod<void>('cancelRead', {'streamId': streamId});
    } on PlatformException {
      // The native stream may already have ended naturally.
    }
  }
}
