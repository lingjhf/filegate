# Changelog

## 1.7.1 - 2026-05-24

### Fixed

- Kept iOS read event channels registered until Flutter deactivates the stream,
  avoiding `MissingPluginException` during read stream teardown.
- Ignored Dart-side dynamic event-channel cancellation failures after a read
  stream has already ended.

## 1.7.0 - 2026-05-21

### Changed

- Updated Dart constructors to use private named initializing formals where
  available with Dart 3.12.

## 1.6.0 - 2026-05-19

### Added

- Added Dart-side streamed write progress callbacks for `openWrite()` and
  `writeStream()`.

## 1.5.0 - 2026-05-19

### Added

- Added Dart APIs and method-channel contract for streamed file writing with
  cancellable write sessions.
- Implemented streamed append/replace writes in the native plugins and covered
  them in the example app and integration tests.

## 1.4.0 - 2026-05-18

### Added

- Added a direct file save API contract for writing in-memory bytes through
  native save/export dialogs across supported platforms.
- Added a direct file write API contract for replacing or appending bytes to
  existing files across supported platforms.
- Implemented direct append/replace writing in the native plugins and covered
  it in the example app and integration tests.

### Fixed

- Prevented Dart read-session cancellation from hanging if `cancel()` is called
  before the native `startRead` call returns a stream id.

## 1.3.3 - 2026-05-16

### Fixed

- Kept Android read event-channel handlers registered until Flutter
  deactivates the stream, avoiding `MissingPluginException` after EOF while
  still releasing file handles promptly.

## 1.3.2 - 2026-05-16

### Changed

- Enabled strict Dart analyzer language checks for the plugin and example.
- Added explicit example analysis to the local release validation script.

## 1.3.1 - 2026-05-16

### Fixed

- Added public `FilegateErrorCode` constants for stream protocol failures
  (`missing_stream_id` and `invalid_chunk`) and used shared constants in
  Dart-side platform errors.

## 1.3.0 - 2026-05-16

### Fixed

- Released Android native file handles after EOF and read-open failures while
  keeping stream channels available for Flutter deactivation.
- Cancelled native read sessions when Dart receives invalid stream payloads
  or event-channel errors.

## 1.2.1 - 2026-05-16

### Fixed

- Sorted picker results by stable relative path/name/path keys after
  native decoding and directory enumeration so result order is deterministic
  across supported platforms.

## 1.2.0 - 2026-05-16

### Changed

- Updated iOS and macOS mixed picking so selected directories are expanded into
  matching file entries instead of being returned as directory entries.

## 1.1.1 - 2026-05-16

### Fixed

- Normalized allowed file extensions consistently across Dart and native
  picker paths by trimming whitespace, removing leading dots, lowercasing,
  dropping empty values, and deduplicating entries.

## 1.1.0 - 2026-05-16

### Added

- Populated best-effort picker metadata from native file entries across
  Android, iOS, macOS, Windows, and Linux.
- Displayed available picker metadata in the example app file and directory
  picker pages.

## 1.0.3 - 2026-05-16

### Fixed

- Added Dart-side validation for public read arguments before dispatching to
  platform implementations.
- Rejected negative `readAllBytes(maxBytes:)` values before opening a stream.
- Kept `openReadWithProgress()` best-effort when file-size lookup fails with
  non-platform errors.
- Capped `FileReadChunk.progress` at `1.0` when a stream yields more bytes than
  the reported total.

## 1.0.2 - 2026-05-16

### Fixed

- Aligned native directory enumeration across Android, iOS, macOS, Windows,
  and Linux so returned `relativePath` values are relative to the selected
  root directory instead of being prefixed by the root directory name.

### Changed

- Updated example and integration test expectations to document root-relative
  directory paths.
- Clarified the local release validation script's handling of pub.dev dry-run
  hints when local release commits have not been published.

## 1.0.1 - 2026-05-16

### Fixed

- Restored the default platform interface after each Dart unit test to keep
  tests isolated under randomized execution order.
- Replaced open-ended integration test settling with bounded frame pumps so
  desktop test runners cannot hang during route animations.

### Changed

- Added a local release validation script that runs dependency resolution,
  analysis, package tests, example tests, macOS integration tests, pub.dev
  dry-run validation, and diff whitespace checks.
- Allowed the validation script to tolerate pub.dev dry-run's expected dirty
  git warning while release files are still uncommitted.

## 1.0.0 - 2026-05-16

### Changed

- Promoted the validated API contract to the stable 1.0 release track.
- Expanded release validation coverage for stable error codes and ranged
  progress reads.

## 0.8.0 - 2026-05-16

### Added

- Added an API contract document for the 1.0 release track.
- Added a capabilities page to the example app to demonstrate
  `Filegate.getCapabilities()`.

## 0.7.0 - 2026-05-16

### Fixed

- Hardened native stream readers so Android, iOS, and macOS honor the
  exclusive `end` offset for ranged `openRead()` calls.

## 0.6.0 - 2026-05-16

### Added

- Added `Filegate.listDirectoryFiles()` for enumerating files from a known
  file-system directory path with extension filtering and metadata.

## 0.5.0 - 2026-05-16

### Added

- Added `Filegate.readByteRange()` for bounded range reads built on the
  streamed reader.
- Added optional exclusive `end` offsets to `openRead()` and
  `openReadWithProgress()`.

## 0.4.0 - 2026-05-16

### Added

- Added `persistAccess` picker options so callers can request one-session
  access instead of persisted URI permission on Android.

## 0.3.0 - 2026-05-16

### Added

- Added `PickedEntryMetadata` and metadata helpers on `PickedEntry` for
  optional file size, modification time, and MIME type values.

## 0.2.0 - 2026-05-16

### Added

- Added `FilegateLocationKind` and `PickedEntry` location helpers for
  distinguishing platform paths, `file:` URIs, Android `content:` URIs, and
  other URI identifiers.

## 0.1.0 - 2026-05-16

### Added

- Added `Filegate.getCapabilities()` and `FilegateCapabilities` to expose
  platform support for file picking, directory picking, mixed picking, initial
  directories, persisted access, and native URI reads.

## 0.0.4 - 2026-05-16

### Fixed

- Exposed native picker failure error codes in `FilegateErrorCode`.

### Changed

- Added pub.dev dry-run validation to pull request CI.
- Isolated Windows native test builds from Windows integration test builds in
  CI.
- Documented the release validation checklist.

## 0.0.3 - 2026-05-16

### Fixed

- Fixed decoding of native integer-list read chunks from platform channels.
- Hardened native read stream cancellation on Android, iOS, and macOS.

### Changed

- Added Android native and emulator integration test coverage in CI.
- Raised Dart unit test line coverage above 90%.

## 0.0.2 - 2026-05-16

### Added

- Added native Windows and Linux picker implementations.
- Added Windows and Linux CI branches that run package tests, example widget tests, native tests, and integration tests independently.

## 0.0.1 - 2026-05-16

### Added

- Initial native file picker implementation for Android, iOS, macOS, Windows, and Linux.
- Added Dart APIs for picking files, picking directory contents, reading file sizes, streamed file reads, progress reads, and bounded full-file reads.
- Added example app pages for files, directories, and file byte previews.
- Added package tests, example widget tests, macOS integration tests, and GitHub Actions CI.
