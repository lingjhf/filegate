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
- `pickMixed()` returns both files and directory contents on platforms whose
  native picker supports mixed selection. Android, Windows, and Linux return
  `FilegateErrorCode.unsupportedMode`.
- `FilegatePickOptions.persistAccess` defaults to `true`. Android uses it to
  request persisted Storage Access Framework URI permission when the system
  grants one. Other platforms may ignore the flag.

## Entry identity

- `PickedEntry.path` is the stable identifier returned by the platform. It may
  be a file-system path, `file:` URI, Android `content:` URI, or another URI
  form.
- `PickedEntry.fileSystemPath` is non-null for platform paths and `file:` URIs.
  It is null for identifiers that cannot be represented as a direct local path.
- `PickedEntry.metadata` is best effort. Consumers should handle missing
  `size`, `modifiedAt`, and `mimeType` values.

## Reading

- `openRead(path)` returns a cancellable byte stream.
- `start` is inclusive. `end` is exclusive. If `end` is omitted, reading
  continues until EOF. If `start >= end`, the stream completes without chunks.
- `readByteRange(path, start: s, length: n)` reads at most `n` bytes using the
  same `[start, end)` semantics.
- `readAllBytes()` is a convenience API for small files. Use `openRead()` for
  large files or untrusted file sizes.
- `cancel()` is idempotent. Consumers may call it after stream completion.

## Directory listing

- `listDirectoryFiles()` lists files from a known file-system directory without
  opening a picker.
- Returned entries are sorted by `relativePath`.
- `allowedExtensions` are case-insensitive and may be supplied with or without
  a leading dot.
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
- `stream_active`
- `read_open_failed`
- `read_failed`
- `enumeration_failed`
