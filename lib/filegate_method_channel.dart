import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'filegate_platform_interface.dart';
import 'src/desktop_file_reader.dart';
import 'src/errors.dart';
import 'src/file_arguments.dart';
import 'src/file_read_session.dart';
import 'src/file_write_session.dart';
import 'src/models.dart';
import 'src/native_file_reader.dart';
import 'src/read_arguments.dart';

/// An implementation of [FilegatePlatform] that uses method channels.
class MethodChannelFilegate extends FilegatePlatform {
  MethodChannelFilegate({
    @visibleForTesting this.forceNativeRead = false,
    @visibleForTesting String? operatingSystem,
  }) : _operatingSystem = operatingSystem ?? Platform.operatingSystem;

  final bool forceNativeRead;
  final String _operatingSystem;

  @visibleForTesting
  final methodChannel = const MethodChannel('filegate');

  @override
  Future<FilegateCapabilities> getCapabilities() async {
    return capabilitiesForOperatingSystem(_operatingSystem);
  }

  @visibleForTesting
  static FilegateCapabilities capabilitiesForOperatingSystem(
    String operatingSystem,
  ) {
    return switch (operatingSystem) {
      'android' => const FilegateCapabilities(
        supportsFilePicking: true,
        supportsDirectoryPicking: true,
        supportsMixedPicking: false,
        supportsInitialDirectory: true,
        supportsPersistedAccess: true,
        supportsNativeUriRead: true,
        supportsFileSaving: true,
        supportsFileWriting: true,
        supportsFileStreamWriting: true,
        supportsMediaPicking: true,
        supportsGallerySaving: true,
      ),
      'ios' => const FilegateCapabilities(
        supportsFilePicking: true,
        supportsDirectoryPicking: true,
        supportsMixedPicking: true,
        supportsInitialDirectory: true,
        supportsPersistedAccess: false,
        supportsNativeUriRead: true,
        supportsFileSaving: true,
        supportsFileWriting: true,
        supportsFileStreamWriting: true,
        supportsMediaPicking: true,
        supportsGallerySaving: true,
      ),
      'macos' => const FilegateCapabilities(
        supportsFilePicking: true,
        supportsDirectoryPicking: true,
        supportsMixedPicking: true,
        supportsInitialDirectory: true,
        supportsPersistedAccess: true,
        supportsNativeUriRead: false,
        supportsFileSaving: true,
        supportsFileWriting: true,
        supportsFileStreamWriting: true,
      ),
      'windows' => const FilegateCapabilities(
        supportsFilePicking: true,
        supportsDirectoryPicking: true,
        supportsMixedPicking: false,
        supportsInitialDirectory: true,
        supportsPersistedAccess: true,
        supportsNativeUriRead: false,
        supportsFileSaving: true,
        supportsFileWriting: true,
        supportsFileStreamWriting: true,
      ),
      'linux' => const FilegateCapabilities(
        supportsFilePicking: true,
        supportsDirectoryPicking: true,
        supportsMixedPicking: false,
        supportsInitialDirectory: true,
        supportsPersistedAccess: true,
        supportsNativeUriRead: false,
        supportsFileSaving: true,
        supportsFileWriting: true,
        supportsFileStreamWriting: true,
      ),
      _ => const FilegateCapabilities(
        supportsFilePicking: false,
        supportsDirectoryPicking: false,
        supportsMixedPicking: false,
        supportsInitialDirectory: false,
        supportsPersistedAccess: false,
        supportsNativeUriRead: false,
      ),
    };
  }

  @override
  Future<List<PickedEntry>?> pick(FilegatePickOptions options) async {
    final entries = await methodChannel.invokeListMethod<Object?>(
      'pick',
      options.toMap(),
    );

    return _decodePickedEntries(entries);
  }

  @override
  Future<List<PickedEntry>?> pickMedia(FilegateMediaPickOptions options) async {
    final entries = await methodChannel.invokeListMethod<Object?>(
      'pickMedia',
      options.toMap(),
    );

    return _decodePickedEntries(entries);
  }

  List<PickedEntry>? _decodePickedEntries(List<Object?>? entries) {
    if (entries == null) {
      return null;
    }

    final uniqueEntries = <String, PickedEntry>{};
    for (final entry in entries) {
      final decodedEntry = PickedEntry.fromMap(_castMap(entry));
      uniqueEntries.putIfAbsent(decodedEntry.path, () => decodedEntry);
    }

    return uniqueEntries.values.toList(growable: false)
      ..sort(_comparePickedEntries);
  }

  @override
  Future<PickedEntry?> save(FilegateSaveOptions options) async {
    validateFileName(options.suggestedName, argumentName: 'suggestedName');

    final entry = await methodChannel.invokeMapMethod<Object?, Object?>(
      'save',
      options.toMap(),
    );

    if (entry == null) {
      return null;
    }

    return PickedEntry.fromMap(entry);
  }

  @override
  Future<FilegateGallerySaveResult> saveToGallery(
    FilegateGallerySaveOptions options,
  ) async {
    if (_operatingSystem != 'android' && _operatingSystem != 'ios') {
      throw PlatformException(
        code: FilegateErrorCode.unsupportedMode,
        message:
            'Saving media to the system gallery is supported on Android and iOS only.',
      );
    }

    final result = await methodChannel.invokeMapMethod<Object?, Object?>(
      'saveToGallery',
      options.toMap(),
    );

    return FilegateGallerySaveResult.fromMap(_castMap(result));
  }

  @override
  Future<PickedEntry> write(FilegateWriteOptions options) async {
    validateNonEmptyPath(options.path);

    final entry = await methodChannel.invokeMapMethod<Object?, Object?>(
      'write',
      options.toMap(),
    );

    return PickedEntry.fromMap(_castMap(entry));
  }

  @override
  Future<FileWriteSession> openWrite(
    String path, {
    FilegateWriteMode mode = FilegateWriteMode.replace,
  }) async {
    validateNonEmptyPath(path);

    final sessionId = await methodChannel.invokeMethod<String>('startWrite', {
      'path': path,
      'mode': mode.name,
    });

    if (sessionId == null || sessionId.isEmpty) {
      throw PlatformException(
        code: FilegateErrorCode.missingWriteSessionId,
        message: 'Native writer did not return a session identifier.',
      );
    }

    return FileWriteSession(
      onAdd: (chunk) {
        return methodChannel.invokeMethod<void>('writeChunk', {
          'sessionId': sessionId,
          'bytes': chunk,
        });
      },
      onClose: () async {
        final entry = await methodChannel.invokeMapMethod<Object?, Object?>(
          'finishWrite',
          {'sessionId': sessionId},
        );
        return PickedEntry.fromMap(_castMap(entry));
      },
      onCancel: () => _cancelWrite(sessionId),
    );
  }

  @override
  Future<int?> getFileSize(String path) async {
    validateNonEmptyPath(path);

    final size = await methodChannel.invokeMethod<num?>('getFileSize', {
      'path': path,
    });
    return size?.toInt();
  }

  @override
  FileReadSession<Uint8List> openRead(
    String path, {
    int chunkSize = 64 * 1024,
    int start = 0,
    int? end,
  }) {
    validateReadArguments(path, chunkSize: chunkSize, start: start, end: end);

    if (!forceNativeRead &&
        (_operatingSystem == 'macos' ||
            _operatingSystem == 'windows' ||
            _operatingSystem == 'linux')) {
      return DesktopFileReader(
        path: path,
        chunkSize: chunkSize,
        start: start,
        end: end,
      ).session;
    }
    return NativeFileReader(
      channel: methodChannel,
      path: path,
      chunkSize: chunkSize,
      start: start,
      end: end,
    ).session;
  }

  Future<void> _cancelWrite(String sessionId) async {
    try {
      await methodChannel.invokeMethod<void>('cancelWrite', {
        'sessionId': sessionId,
      });
    } on PlatformException {
      // Ignore cancellation failures because the consumer already requested
      // shutdown and the native write session may have ended naturally.
    }
  }

  static Map<Object?, Object?> _castMap(Object? value) {
    if (value is Map<Object?, Object?>) {
      return value;
    }
    throw ArgumentError.value(
      value,
      'value',
      'Expected a map from the native layer',
    );
  }

  static int _comparePickedEntries(PickedEntry left, PickedEntry right) {
    final keyComparison = _pickedEntrySortKey(
      left,
    ).compareTo(_pickedEntrySortKey(right));
    if (keyComparison != 0) {
      return keyComparison;
    }
    final nameComparison = left.name.compareTo(right.name);
    if (nameComparison != 0) {
      return nameComparison;
    }
    return left.path.compareTo(right.path);
  }

  static String _pickedEntrySortKey(PickedEntry entry) {
    return entry.relativePath?.replaceAll(r'\', '/') ?? entry.name;
  }
}
