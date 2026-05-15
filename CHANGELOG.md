# Changelog

## Unreleased

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
