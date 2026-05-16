# Release checklist

Run this checklist before every version commit.

1. Review the Dart API, platform code, tests, example app, documentation, and CI
   changes touched by the release.
2. Fix all review findings that affect the release behavior or package quality.
3. Run static analysis and package tests.
4. Run example widget tests and the platform integration tests available on the
   current machine.
5. Run native platform tests available on the current machine.
6. Run `flutter pub publish --dry-run`.
7. Update `pubspec.yaml`, `CHANGELOG.md`, and public documentation.
8. Commit the release as `release: filegate x.y.z`.

The local release gate is captured in `tool/run_release_checks.sh`.

Do not create a semver tag unless the package should be published to pub.dev.
