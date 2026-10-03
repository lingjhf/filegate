import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

import 'errors.dart';
import 'file_location.dart';
import 'file_read_session.dart';

class DesktopFileReader {
  DesktopFileReader({
    required this.path,
    required this.chunkSize,
    required this.start,
    required this.end,
  }) {
    _controller = StreamController<Uint8List>(
      onListen: _start,
      onResume: _resume,
      onCancel: cancel,
    );
    session = FileReadSession(stream: _controller.stream, onCancel: cancel);
  }

  final String path;
  final int chunkSize;
  final int start;
  final int? end;
  late final FileReadSession<Uint8List> session;
  late final StreamController<Uint8List> _controller;
  RandomAccessFile? _file;
  bool _cancelled = false;
  bool _closed = false;
  Future<void>? _readFuture;
  Future<void>? _cancelFuture;
  Completer<void>? _resumeSignal;

  void _start() {
    if (!_cancelled) _readFuture = _read();
  }

  void _resume() {
    _resumeSignal?.complete();
    _resumeSignal = null;
  }

  void _finish() {
    if (_closed) return;
    _closed = true;
    // Stream completion can wait for a paused listener; cleanup must not.
    unawaited(_controller.close());
  }

  Future<void> cancel() {
    return _cancelFuture ??= () async {
      _cancelled = true;
      _resume();
      // The producer owns the handle, including pending open/read operations.
      await _readFuture;
      _finish();
    }();
  }

  Future<void> _read() async {
    var opened = false;
    try {
      final localPath = desktopReadPath(path);
      if (localPath == null) {
        throw PlatformException(
          code: FilegateErrorCode.unsupportedMode,
          message: 'The provided identifier is not a local file path.',
          details: path,
        );
      }
      final type = await FileSystemEntity.type(localPath);
      if (_cancelled) return;
      if (type == FileSystemEntityType.notFound) {
        throw PlatformException(
          code: FilegateErrorCode.pathNotFound,
          message: 'The provided path does not exist.',
          details: path,
        );
      }
      if (type == FileSystemEntityType.directory) {
        throw PlatformException(
          code: FilegateErrorCode.notAFile,
          message: 'The provided path is a directory, not a file.',
          details: path,
        );
      }

      final handle = await File(localPath).open();
      _file = handle;
      opened = true;
      if (_cancelled) return;
      final length = await handle.length();
      final endOffset = end == null || end! > length ? length : end!;
      if (_cancelled || start >= endOffset) return;

      var offset = start;
      await handle.setPosition(offset);
      while (!_cancelled && offset < endOffset) {
        while (!_cancelled && _controller.isPaused) {
          await (_resumeSignal ??= Completer<void>()).future;
        }
        if (_cancelled) break;
        final remainingBytes = endOffset - offset;
        final chunk = await handle.read(
          remainingBytes < chunkSize ? remainingBytes : chunkSize,
        );
        if (_cancelled || chunk.isEmpty) break;
        offset += chunk.length;
        _controller.add(chunk);
      }
    } catch (error, stackTrace) {
      if (!_cancelled) {
        _controller.addError(_mapError(error, opened), stackTrace);
      }
    } finally {
      try {
        await _file?.close();
      } catch (error, stackTrace) {
        if (!_cancelled) _controller.addError(error, stackTrace);
      }
      _file = null;
      _finish();
    }
  }

  Object _mapError(Object error, bool opened) {
    if (error is! FileSystemException) return error;
    final osCode = error.osError?.errorCode;
    final missing = osCode == 2 || (Platform.isWindows && osCode == 3);
    final denied = Platform.isWindows
        ? osCode == 5
        : osCode == 1 || osCode == 13;
    return PlatformException(
      code: missing
          ? FilegateErrorCode.pathNotFound
          : denied
          ? FilegateErrorCode.permissionDenied
          : opened
          ? FilegateErrorCode.readFailed
          : FilegateErrorCode.readOpenFailed,
      message: error.message,
      details: path,
    );
  }
}
