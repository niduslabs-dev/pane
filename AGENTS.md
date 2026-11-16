# Pane

A Mac app that mirrors a running Android emulator in a clean window, inside a device frame we draw, and forwards clicks and frame-button presses to it over the emulator's own gRPC interface (`EmulatorController`). Android emulator only. Status: spike (discovery, live frames, tap, frame buttons).

- Plan and decisions: `../plans/pane.md` (Nidus Labs workspace). Research with sources: `~/Work/personal/.claude/research/emulator-mirror-grpc.md`.
- Design canvas: [Pane design](https://claude.ai/artifact/SSy48PyDrNEapFzTWwoybJ). Studio design rules: `../docs/mac-app-design.md`.

## Layout

A Swift package, no Xcode project. Swift 6, strict concurrency, macOS 15+.

- `PaneCore` (no UI): `Discovery/` reads `~/Library/Caches/TemporaryItems/avd/running/pid_*.ini` (port, token, AVD) and the AVD's `config.ini`, and watches the folder; `Client/EmulatorConnection` is the plaintext HTTP/2 gRPC client with the bearer token, `streamScreenshot` (RGBA8888, both width and height set) and one long-lived `streamInputEvent`; `Geometry/` maps window points to device pixels and lays out the frame; `Generated/` is protoc output, committed.
- `Pane`: the app. `Theme.swift` holds every size and colour (from the board); `PaneModel` owns the connection and the input rules; `ScreenView` draws frames as a `CGImage` on a layer (Metal is v1); `PaneContentView` is the title row and the drawn frame.
- `Protos/`: the vendored proto and the emulator version it came from.

## Commands

Homebrew's LLVM env breaks Xcode builds, so build through `scripts/swift.sh`, which clears it:

```sh
scripts/swift.sh build
scripts/swift.sh test
scripts/build-app.sh [--debug]     # build/Pane.app, ad hoc signed
scripts/format.sh                   # swift format; --lint for the strict check
scripts/generate-protos.sh          # regenerate Sources/PaneCore/Generated (pinned protoc in .claude/tools)
```

**Checking the app without taking focus** (`.claude/checks/`, gitignored): launch with `open -g build/Pane.app` (append `--args -NSRequiresAquaSystemAppearance YES` for light), find the window with `window-info.swift <pid>`, capture with `screencapture -l <id> -o -x`, and click with `click <pid> <windowID> <x> <y> [hold] [toX toY steps]` (window-local points; it posts an `NSEvent`'s `CGEvent` to the PID, so nothing activates). The debug build logs pointer, key and per-second frame stats (fps, drops, latency) under subsystem `dev.niduslabs.pane`. Quit by PID.

## Conventions

- **Never log or print the gRPC token.** `GRPCToken` redacts every textual form; only the `authorization` header sees it.
- **Every press ends in a release:** mouse up, drag off the screen, pointer exit, window or app losing focus.
- **Dependencies pinned with `exact:`** and `Package.resolved` committed. gRPC Swift 2 needs macOS 15.
- **Generated code is committed and never edited.** To update: copy the new proto into `Protos/`, note its emulator version there, run `scripts/generate-protos.sh`.
- **Theme constants only;** views hold no raw numbers. Format and lint with Apple's `swift format` (`.swift-format`, lint `--strict` clean); generated code is excluded.
- **Unsandboxed:** the App Sandbox blocks the registration folder.
- **One agent drives the emulator at a time** (shared device, see the workspace guide).
