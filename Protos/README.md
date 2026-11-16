# Protos

`emulator_controller.proto` is copied unchanged from the Android Emulator **37.2.13** (build 16740729),
`~/Library/Android/sdk/emulator/lib/emulator_controller.proto`. Its only import,
`google/protobuf/empty.proto`, comes from the pinned `protoc` release's `include/` folder.

The generated Swift in `Sources/PaneCore/Generated/` is committed. Regenerate with
`scripts/generate-protos.sh` after copying a newer proto here, and update the version above.
