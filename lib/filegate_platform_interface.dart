import 'dart:typed_data';

import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'filegate_method_channel.dart';
import 'src/file_read_session.dart';
import 'src/models.dart';

abstract class FilegatePlatform extends PlatformInterface {
  /// Constructs a FilegatePlatform.
  FilegatePlatform() : super(token: _token);

  static final Object _token = Object();

  static FilegatePlatform _instance = MethodChannelFilegate();

  /// The default instance of [FilegatePlatform] to use.
  ///
  /// Defaults to [MethodChannelFilegate].
  static FilegatePlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [FilegatePlatform] when
  /// they register themselves.
  static set instance(FilegatePlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<FilegateCapabilities> getCapabilities() {
    throw UnimplementedError('getCapabilities() has not been implemented.');
  }

  Future<List<PickedEntry>?> pick(FilegatePickOptions options) {
    throw UnimplementedError('pick() has not been implemented.');
  }

  Future<PickedEntry?> save(FilegateSaveOptions options) {
    throw UnimplementedError('save() has not been implemented.');
  }

  Future<int?> getFileSize(String path) {
    throw UnimplementedError('getFileSize() has not been implemented.');
  }

  FileReadSession<Uint8List> openRead(
    String path, {
    int chunkSize = 64 * 1024,
    int start = 0,
    int? end,
  }) {
    throw UnimplementedError('openRead() has not been implemented.');
  }
}
