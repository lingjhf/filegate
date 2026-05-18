# filegate API contract

This document freezes the public API behavior used for the 1.0 release track.
Patch and minor releases may add APIs, but existing methods should keep the
semantics below unless a future changelog calls out a breaking change.

## Picking

- `pickFiles()` returns selected files or `null` when the picker is cancelled.
- `pickDirectoryFiles()` returns files found inside the selected directory.
  Returned entries should include `relativePath` when the platform can provide
  a stable path relative to the selected root, without prefixing the selected
  root directory name.
- `pickMixed()` returns selected files and files enumerated from selected
  directories on platforms whose native picker supports mixed selection.
  Android, Windows, and Linux return `FilegateErrorCode.unsupportedMode`.
- Picker results are deduplicated by `PickedEntry.path` and sorted by
  `relativePath`, then `name`, then `path`.
- `FilegatePickOptions.persistAccess` defaults to `true`. Android uses it to
  request persisted Storage Access Framework URI permission when the system
  grants one. Other platforms may ignore the flag.

## Entry identity

- `PickedEntry.path` is the stable identifier returned by the platform. It may
  be a file-system path, `file:` URI, Android `content:` URI, or another URI
  form.
- `PickedEntry.fileSystemPath` is non-null for platform paths and `file:` URIs.
  It is null for identifiers that cannot be represented as a direct local path.
- `PickedEntry.metadata` is best effort. Native pickers should include `size`,
  `modifiedAt`, and `mimeType` when the platform exposes stable values.
  Consumers should still handle missing values.

## Reading

- `openRead(path)` returns a cancellable byte stream.
- `start` is inclusive. `end` is exclusive. If `end` is omitted, reading
  continues until EOF. If `start >= end`, the stream completes without chunks.
- `readByteRange(path, start: s, length: n)` reads at most `n` bytes using the
  same `[start, end)` semantics.
- `readAllBytes()` is a convenience API for small files. Use `openRead()` for
  large files or untrusted file sizes. `maxBytes`, when provided, must not be
  negative.
- `cancel()` is idempotent. Consumers may call it after stream completion.
- Native read file handles are released after EOF or read-open failures.
  Native event-channel registrations remain available until Flutter
  deactivates the stream.

## Saving

- `saveFile(bytes, suggestedName: name)` opens the platform save/export UI,
  writes the provided bytes after the user confirms, and returns a
  `PickedEntry` for the saved file.
- If the user cancels the save/export UI, `saveFile()` returns `null`.
- `suggestedName` must be a non-empty file name, not a path. Empty byte
  payloads are valid and create an empty file when the platform accepts them.
- `allowedExtensions` are normalized with the same rules as picker options and
  are used as platform save dialog filters where the platform supports them.
- Save results should include best-effort metadata for the saved file when the
  platform can provide it.
- Direct save is one-shot and memory-backed. It creates or replaces the target
  chosen by the platform save/export UI.

## Writing

- `writeFile(path, bytes, mode: mode)` writes to an existing file path or URI
  without opening a picker.
- `FilegateWriteMode.replace` truncates the target before writing.
- `FilegateWriteMode.append` writes at the end of the existing target.
- Empty byte payloads are valid. Replace mode truncates to an empty file, and
  append mode leaves the file contents unchanged.
- If the target does not exist, is a directory, or cannot be accessed, native
  implementations surface the corresponding `FilegateErrorCode`.
- Write results should include best-effort metadata for the updated file when
  the platform can provide it.
- Streaming writes and append-through-save-dialog behavior are intentionally
  outside this contract.

## Directory listing

- `listDirectoryFiles()` lists files from a known file-system directory without
  opening a picker.
- Returned entries are sorted by `relativePath`.
- `allowedExtensions` are trimmed, case-insensitive, deduplicated, and may be
  supplied with or without a leading dot.
- Symbolic links are not followed.

## Errors

Native failures are surfaced as `PlatformException`s with
`FilegateErrorCode` values. The stable error codes are:

- `invalid_args`
- `unsupported_mode`
- `no_activity`
- `no_view_controller`
- `picker_active`
- `path_not_found`
- `not_a_file`
- `not_a_directory`
- `permission_denied`
- `persist_permission_failed`
- `security_scope_failed`
- `pick_failed`
- `picker_failed`
- `save_failed`
- `write_failed`
- `stream_active`
- `missing_stream_id`
- `invalid_chunk`
- `read_open_failed`
- `read_failed`
- `enumeration_failed`
