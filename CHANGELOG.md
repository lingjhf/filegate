# Changelog

## Unreleased

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
