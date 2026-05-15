# filegate

A Flutter plugin for native file picking and streamed file reading.

The plugin exposes a Dart API for picking files or directory contents, querying
file size, and reading files in chunks without loading the whole file into
memory first.

## Supported platforms

- Android
- iOS
- macOS
- Windows
- Linux

All supported platforms provide native picker implementations. Desktop file
reading for paths available to Dart uses `dart:io`.

## Installation

Add the package to your app:

```yaml
dependencies:
  filegate: ^0.0.3
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
- Mixed file and directory selection returns selected files and directory
  entries.

### macOS

File picking uses `NSOpenPanel`. The macOS plugin target requires macOS 11.0 or
newer.

- Directory selection enumerates matching files from the selected directory.
- Mixed file and directory selection returns selected files and directory
  entries.

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
  allowedExtensions: ['txt', 'json'],
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

## API

### Filegate

`Filegate` is the main entry point.

Methods:

- `pick(FilegatePickOptions options)`: Runs a platform picker.
- `pickFiles(...)`: Picks one or more files.
- `pickDirectoryFiles(...)`: Picks a directory and returns matching files.
- `pickMixed(...)`: Picks files and directories where supported.
- `getFileSize(String path)`: Returns a file size when known.
- `openRead(String path, {int chunkSize, int start})`: Opens a cancellable byte stream.
- `openReadWithProgress(String path, {int chunkSize})`: Streams chunks with cumulative progress.
- `readAllBytes(String path, {int chunkSize, int? maxBytes})`: Reads all bytes with an optional safety limit.

### PickedEntry

`PickedEntry` describes a selected file or directory entry.

Fields:

- `path`: Platform path or URI.
- `name`: Display name.
- `kind`: `PickedEntryKind.file` or `PickedEntryKind.directory`.
- `relativePath`: Relative path when enumerating directory contents.

## Errors

Native failures are surfaced as `PlatformException`s. Common error codes are
available in `FilegateErrorCode`, including `invalid_args`, `unsupported_mode`,
`permission_denied`, `path_not_found`, `not_a_file`, `pick_failed`,
`picker_failed`, and `read_failed`.
