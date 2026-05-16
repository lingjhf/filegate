#!/usr/bin/env sh
set -eu

flutter pub get

(
  cd example
  flutter pub get
)

flutter analyze
flutter test --test-randomize-ordering-seed=random

(
  cd example
  flutter test test/widget_test.dart
  flutter test --timeout=20m integration_test/plugin_integration_test.dart -d macos
)

publish_output="$(mktemp)"
if flutter pub publish --dry-run >"$publish_output" 2>&1; then
  cat "$publish_output"
else
  cat "$publish_output"
  if grep -q "checked-in files are modified in git" "$publish_output" &&
    grep -q "Package has 1 warning." "$publish_output"; then
    echo "Ignoring expected dirty git warning during pre-commit dry-run."
  else
    rm -f "$publish_output"
    exit 1
  fi
fi
rm -f "$publish_output"

git diff --check
