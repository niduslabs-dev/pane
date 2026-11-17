#!/bin/sh
# The checks every release passes, shared by ci.yml and release.yml so the two can't drift:
# lint, then build and run the tests (debug).
#
# Usage: .github/scripts/test.sh [lint] [build] [test]   (no argument: all three, in order)
set -eu
cd "$(dirname "$0")/../.."
[ $# -gt 0 ] || set -- lint build test
for STEP in "$@"; do
    echo "::group::$STEP"
    case $STEP in
        lint) scripts/format.sh --lint ;;
        build) scripts/swift.sh build --build-tests ;;
        test) scripts/swift.sh test --skip-build ;;
        *) echo "unknown step: $STEP" >&2; exit 2 ;;
    esac
    echo "::endgroup::"
done
