# filegate

A Flutter plugin for native file picking, direct file saving, direct file
writing, streamed file writing, and streamed file reading.

The plugin exposes a Dart API for picking files or directory contents, saving
bytes through native save/export dialogs, writing bytes to existing files,
writing streams to existing files, querying file size, and reading files in
chunks without loading the whole file into memory first.

## Supported platforms

- Android
- iOS
- macOS
- Windows
- Linux

All supported platforms provide native picker implementations. Desktop file
reading for paths available to Dart uses `dart:io`.

## Feature comparison

Compared with this package (`filegate` 1.5.0) and the latest stable pub.dev
versions checked on 2026-05-18:
[`file_selector` 1.1.0](https://pub.dev/packages/file_selector) and
[`file_picker` 11.0.2](https://pub.dev/packages/file_picker).

`✓` means supported. A blank cell means unsupported or not provided as a
package-level feature.

| Feature | `filegate` | `file_selector` | `file_picker` |
| --- | :---: | :---: | :---: |
| Android support | ✓ | ✓ | ✓ |
| iOS support | ✓ | ✓ | ✓ |
| macOS support | ✓ | ✓ | ✓ |
| Windows support | ✓ | ✓ | ✓ |
| Linux support | ✓ | ✓ | ✓ |
| Web support |  | ✓ | ✓ |
| Single file picking | ✓ | ✓ | ✓ |
| Multiple file picking | ✓ | ✓ | ✓ |
| Extension filtering | ✓ | ✓ | ✓ |
| MIME type filtering |  | ✓ |  |
| UTI filtering |  | ✓ |  |
| Directory picking | ✓ | ✓ | ✓ |
| Directory enumeration | ✓ |  |  |
| Recursive directory enumeration | ✓ |  |  |
| Mixed file and directory picking | ✓ |  | ✓ |
| Save dialog / choose output path | ✓ | ✓ | ✓ |
| One-call save byte payload with dialog | ✓ |  | ✓ |
| Save result metadata | ✓ |  |  |
| Direct write to existing path or URI | ✓ |  |  |
| Replace existing file without picker | ✓ |  |  |
| Append to existing file without picker | ✓ |  |  |
| Empty-byte replace/append contract | ✓ |  |  |
| Streamed direct write | ✓ |  |  |
| Streamed write progress callback | ✓ |  |  |
| Cancellable write session | ✓ |  |  |
| Chunked file reading | ✓ | ✓ | ✓ |
| Cancellable read session | ✓ |  |  |
| Read progress helper | ✓ |  |  |
| Byte range helper | ✓ |  |  |
| Read all bytes helper | ✓ | ✓ | ✓ |
| Result file size metadata | ✓ | ✓ | ✓ |
| Result modified time metadata | ✓ | ✓ |  |
| Result MIME type metadata | ✓ | ✓ |  |
| Android persisted URI access option | ✓ |  |  |

`saveFile` is the save/save-as flow for creating or replacing a user-chosen
target. Appending is intentionally modeled as direct writing to an existing
target via `writeFile`, `writeStream`, or `openWrite` with
`FilegateWriteMode.append`.

## Installation

Add the package to your app:

```yaml
dependencies:
  filegate: ^1.5.0
```

If you are using this repository directly:

```yaml
dependencies:
  filegate:
    path: ../filegate
```

Then run:

```sh
flutter pub get
```

## Platform notes

### Android

File picking uses the Android Storage Access Framework.

- File selection uses `ACTION_OPEN_DOCUMENT`.
- Directory selection uses `ACTION_OPEN_DOCUMENT_TREE`.
- Mixed file and directory selection in one picker call is not supported by the
  standard Android SAF intents. `pickMixed` returns `unsupported_mode` on
  Android.

### iOS

File picking uses `UIDocumentPickerViewController`. Returned document URLs are
read using current-session security-scoped access.

- Directory selection enumerates matching files from the selected directory.
- Mixed file and directory selection returns selected files and files
  enumerated from selected directories.

### macOS

File picking uses `NSOpenPanel`. The macOS plugin target requires macOS 11.0 or
newer.

- Directory selection enumerates matching files from the selected directory.
- Mixed file and directory selection returns selected files and files
  enumerated from selected directories.

### Windows

File picking uses `IFileOpenDialog`.

- File selection uses the normal open-file dialog.
- Directory selection uses the same dialog in `FOS_PICKFOLDERS` mode and then
  enumerates matching files from the selected directory.
- Mixed file and directory selection in one picker call is not supported by the
  standard Windows dialog APIs. `pickMixed` returns `unsupported_mode` on
  Windows.

### Linux

File picking uses the GTK file chooser.

- File selection uses `GTK_FILE_CHOOSER_ACTION_OPEN`.
- Directory selection uses `GTK_FILE_CHOOSER_ACTION_SELECT_FOLDER` and then
  enumerates matching files from the selected directory.
- Mixed file and directory selection in one picker call is not supported by the
  standard GTK chooser. `pickMixed` returns `unsupported_mode` on Linux.

## Usage

### Pick files

```dart
import 'package:filegate/filegate.dart';

const filegate = Filegate();

final files = await filegate.pickFiles(
  allowMultiple: true,
  allowedExtensions: ['txt', '.JSON'],
  persistAccess: true,
);

if (files != null) {
  for (final file in files) {
    print(file.path);
  }
}
```

### Pick files from a directory

```dart
final files = await filegate.pickDirectoryFiles(
  recursive: true,
  allowedExtensions: ['md'],
);
```

### Read a file in chunks

```dart
final session = filegate.openRead('/path/to/file.bin');

await for (final chunk in session.stream) {
  print('Read ${chunk.length} bytes');
}
```

### Save bytes to a file

```dart
final saved = await filegate.saveFile(
  Uint8List.fromList('hello\n'.codeUnits),
  suggestedName: 'hello.txt',
  allowedExtensions: ['txt'],
  mimeType: 'text/plain',
);

if (saved != null) {
  print(saved.path);
}
```

### Append bytes to an existing file

```dart
final updated = await filegate.writeFile(
  '/path/to/file.txt',
  Uint8List.fromList('more\n'.codeUnits),
  mode: FilegateWriteMode.append,
);

print(updated.size);
```

### Stream bytes to an existing file

```dart
final updated = await filegate.writeStream(
  '/path/to/file.bin',
  Stream<List<int>>.fromIterable([
    Uint8List.fromList([1, 2, 3]),
    Uint8List.fromList([4, 5, 6]),
  ]),
);

print(updated.size);
```

### Stream bytes with progress

```dart
final updated = await filegate.writeStream(
  '/path/to/file.bin',
  Stream<List<int>>.fromIterable([
    Uint8List.fromList([1, 2, 3]),
    Uint8List.fromList([4, 5, 6]),
  ]),
  totalBytes: 6,
  onProgress: (progress) {
    print(progress.bytesWritten);
    print(progress.progress);
  },
);

print(updated.size);
```

### Read with progress

```dart
final session = filegate.openReadWithProgress('/path/to/file.bin');

await for (final chunk in session.stream) {
  print(chunk.progress);
}
```

### Read all bytes with a limit

```dart
final bytes = await filegate.readAllBytes(
  '/path/to/file.txt',
  maxBytes: 1024 * 1024,
);
```

### Read a byte range

```dart
final header = await filegate.readByteRange(
  '/path/to/file.bin',
  start: 0,
  length: 512,
);
```

### List files in a known directory

```dart
final entries = await filegate.listDirectoryFiles(
  '/path/to/folder',
  recursive: true,
  allowedExtensions: ['txt'],
);
```

## API

The public behavior expected for the 1.0 release track is documented in
[doc/api_contract.md](doc/api_contract.md).

### Filegate

`Filegate` is the main entry point.

Methods:

- `getCapabilities()`: Returns the current platform capability flags.
- `pick(FilegatePickOptions options)`: Runs a platform picker.
- `pickFiles(...)`: Picks one or more files.
- `pickDirectoryFiles(...)`: Picks a directory and returns matching files.
- `pickMixed(...)`: Picks files and directories where supported.
- `saveFile(...)`: Saves an in-memory byte payload through a native save/export
  dialog.
- `writeFile(...)`: Replaces or appends bytes to an existing file path or URI.
- `writeStream(...)`: Replaces or appends streamed byte chunks to an existing
  file path or URI, with optional cumulative progress callbacks.
- `openWrite(...)`: Opens a cancellable write session for manual chunk writes,
  with optional cumulative progress callbacks.
- `getFileSize(String path)`: Returns a file size when known.
- `openRead(String path, {int chunkSize, int start, int? end})`: Opens a
  cancellable byte stream. `start` is inclusive and `end` is exclusive.
- `openReadWithProgress(String path, {int chunkSize, int start, int? end})`: Streams chunks with cumulative progress.
- `readAllBytes(String path, {int chunkSize, int? maxBytes})`: Reads all bytes
  with an optional non-negative safety limit.
- `readByteRange(String path, {int start, int length, int chunkSize})`: Reads
  an exact byte range using the streamed reader.
- `listDirectoryFiles(String directoryPath, {bool recursive, List<String> allowedExtensions})`:
  Lists files from a known file-system directory without opening a picker.

Picker results are deduplicated by platform path/URI and returned in
deterministic relative path, name, then path order. Directory listing results
use the same stable relative path ordering.

### FilegatePickOptions

`persistAccess` defaults to `true` for picker helpers. On Android this asks the
Storage Access Framework to persist the selected URI permission when the system
grants one. Set it to `false` for one-session access.

`allowedExtensions` values are normalized before dispatch: whitespace is
trimmed, leading dots are removed, case is ignored, and duplicates are dropped.

### PickedEntry

`PickedEntry` describes a selected file or directory entry. Picker metadata is
best effort and may be omitted when the platform cannot provide it.

Fields:

- `path`: Platform path or URI.
- `name`: Display name.
- `kind`: `PickedEntryKind.file` or `PickedEntryKind.directory`.
- `relativePath`: Path relative to the selected or listed directory when
  enumerating directory contents.
- `metadata`: Optional `PickedEntryMetadata` supplied by native payloads or
  application code.

Location helpers:

- `locationKind`: `platformPath`, `fileUri`, `contentUri`, or `otherUri`.
- `isUri`: Whether `path` is a URI instead of a platform file path.
- `isContentUri`: Whether `path` is an Android `content:` URI.
- `uri`: Parsed `Uri` when `path` contains a URI scheme.
- `fileSystemPath`: A local file system path for platform paths and `file:`
  URIs, or `null` for identifiers such as Android `content:` URIs.

Metadata helpers:

- `size`: File size in bytes when known.
- `modifiedAt`: Last modified time when known.
- `mimeType`: MIME type when known.

### FilegateCapabilities

`FilegateCapabilities` describes platform differences before showing a picker.
Use it to decide whether to show mixed file/directory selection, initial
directory controls, persistent access messaging, or URI-read flows.

Fields:

- `supportsFilePicking`
- `supportsDirectoryPicking`
- `supportsMixedPicking`
- `supportsInitialDirectory`
- `supportsPersistedAccess`
- `supportsNativeUriRead`
- `supportsFileSaving`
- `supportsFileWriting`
- `supportsFileStreamWriting`

## Errors

Native failures are surfaced as `PlatformException`s. Common error codes are
available in `FilegateErrorCode`, including `invalid_args`,
`unsupported_mode`, `no_activity`, `no_view_controller`, `picker_active`,
`path_not_found`, `not_a_file`, `not_a_directory`, `permission_denied`,
`persist_permission_failed`, `security_scope_failed`, `pick_failed`,
`picker_failed`, `save_failed`, `write_failed`, `stream_active`,
`missing_stream_id`, `missing_write_session_id`, `write_session_not_found`,
`invalid_chunk`, `read_open_failed`, `read_failed`, and `enumeration_failed`.
