#!/bin/sh
# Regenerates the committed Swift in Sources/PaneCore/Generated from Protos/.
#
# protoc is a pinned release binary in the gitignored .claude/tools (no Homebrew), checked
# against the SHA-256 GitHub publishes for the asset. The two plugins are built from the
# exactly pinned packages in Package.swift, so codegen matches the runtime libraries.
#
# Usage: scripts/generate-protos.sh
set -eu
cd "$(dirname "$0")/.."

PROTOC_VERSION=36.2
PROTOC_ASSET="protoc-$PROTOC_VERSION-osx-aarch_64.zip"
PROTOC_SHA256=9cd98a532c5c5e0c4161314de0225de27e4c8a323917b6ea7b1b714d3ae23466
TOOLS=.claude/tools
PROTOC_DIR="$TOOLS/protoc-$PROTOC_VERSION"
PROTOC="$PROTOC_DIR/bin/protoc"

if [ ! -x "$PROTOC" ]; then
    mkdir -p "$PROTOC_DIR"
    timeout 120 curl -fsSL -o "$PROTOC_DIR/$PROTOC_ASSET" \
        "https://github.com/protocolbuffers/protobuf/releases/download/v$PROTOC_VERSION/$PROTOC_ASSET"
    echo "$PROTOC_SHA256  $PROTOC_DIR/$PROTOC_ASSET" | shasum -a 256 -c -
    unzip -q -o "$PROTOC_DIR/$PROTOC_ASSET" -d "$PROTOC_DIR"
fi

timeout 900 scripts/swift.sh build --product protoc-gen-swift
timeout 300 scripts/swift.sh build --product protoc-gen-grpc-swift-2
BIN_DIR=$(scripts/swift.sh build --show-bin-path)

OUT=Sources/PaneCore/Generated
rm -rf "$OUT"
mkdir -p "$OUT"
"$PROTOC" \
    --proto_path=Protos \
    --proto_path="$PROTOC_DIR/include" \
    --plugin=protoc-gen-swift="$BIN_DIR/protoc-gen-swift" \
    --plugin=protoc-gen-grpc-swift="$BIN_DIR/protoc-gen-grpc-swift-2" \
    --swift_out="$OUT" \
    --swift_opt=Visibility=Public \
    --grpc-swift_out="$OUT" \
    --grpc-swift_opt=Visibility=Public,Client=true,Server=false \
    Protos/emulator_controller.proto
echo "Generated into $OUT with protoc $PROTOC_VERSION"
