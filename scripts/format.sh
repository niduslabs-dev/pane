#!/bin/sh
# Formats (default) or lints (--lint) the hand-written Swift with Apple's `swift format`.
# The generated code in Sources/PaneCore/Generated is left as protoc wrote it.
set -eu
cd "$(dirname "$0")/.."
FILES=$(find Sources Tests -name '*.swift' -not -path 'Sources/PaneCore/Generated/*' | sort)
if [ "${1:-}" = "--lint" ]; then
    # shellcheck disable=SC2086
    exec scripts/swift.sh format lint --strict Package.swift $FILES
fi
# shellcheck disable=SC2086
exec scripts/swift.sh format --in-place Package.swift $FILES
