#!/bin/sh
# Runs `swift` with Homebrew's LLVM build env removed, which otherwise breaks Xcode's
# toolchain (wrong clang, headers and linker flags). Usage: scripts/swift.sh build | test ...
PATH=$(printf '%s' "$PATH" | tr ':' '\n' | grep -v /opt/homebrew/opt/llvm | paste -sd: -)
exec env -u CC -u CXX -u CPPFLAGS -u LDFLAGS -u LIBRARY_PATH PATH="$PATH" swift "$@"
