# Pane: how it works and why

The decisions behind Pane and how the mirror works. Moved here from the workspace plan (`studio/pane/plan.md`, deleted 2026-11-19 once Pane shipped; git keeps it). `AGENTS.md` is the map of the code and the rules; this file is the reasoning. Research with sources: `~/Work/personal/.claude/research/emulator-mirror-grpc.md`.

## Goal

A small Mac app that mirrors a running Android emulator in a clean window, inside a device frame we draw ourselves, and forwards clicks, scrolls and keys to it. It replaces the emulator's own window (grey title bar, separate side toolbar) for day-to-day work.

## Decisions (2026-11-16 and 2026-11-17)

- **Android emulator only.** No physical phones (that would need scrcpy's protocol), no iOS Simulator (private Apple frameworks).
- **Transport:** the emulator's own gRPC interface (`EmulatorController`), straight from Swift with gRPC Swift 2. No helper process for the stream. WebRTC isn't in the macOS emulator build.
- **Frame:** our own, drawn from the device's screen size (body, bezel, punch-hole camera, side buttons), so it fits any emulator. Google's Pixel skins aren't bundled or downloaded: their licence is stated only in a sibling file's header, and "Pixel" is a trademark.
- **Frame buttons work** like the iOS Simulator's: nearly flush with a light outline, the nearest slides out when the pointer comes within 24 pt, pushes in while pressed. Click power or volume to press it; holding power is passed through (power menu). Sent as key events over gRPC.
- **No emulator running:** the frame stays and the screen offers Start plus "Choose another emulator", so the window keeps its shape when the emulator boots.
- **Pane starts emulators** as well as attaching to running ones. The emulator runs headless (`-no-window`): Pane is how it is seen. **Pane never starts one on its own**; only Start and Restart do.
- **Chrome matches Apple's Device Hub** (measured with the Accessibility API): traffic lights, then the device name over model and Android version, left-aligned; More as a real toolbar item; under the device a 36 pt glass capsule (Home, Screenshot, Record) and a 36 pt glass circle (Rotate). No full screen: the green button zooms to Fit Screen. Back is an edge swipe.
- **Home and Rotate are our own symbols** drawn by `scripts/make-symbols.py` from measurements of Device Hub's toolbar, never from Apple's artwork.
- **Glass window in light mode too** (Jatin's choice; the studio guide says solid paper). Recorded as a deviation in `AGENTS.md`.
- **Window menu sizes** like the Simulator's: Physical Size, Point Accurate (1 dp = 1 pt), Pixel Accurate (1 px = 1 backing pixel), Fit Screen (Command-1 to 4), Zoom In and Out. Fit Screen the first time, then the last mode per emulator. Pixel Accurate may run past the screen edge, as in Simulator.
- **Record** saves the frames Pane already receives as H.264 `.mov` (variable frame rate, the emulator's frame times). Screenshots are full-size PNGs from the emulator. Both are named like macOS's own captures and go where macOS screenshots go (`location` in `com.apple.screencapture`), else the Desktop.
- **Scrolling is a touch drag,** not `WheelEvent`: phone AVDs have no wheel device, so the emulator drops wheel events.
- **Menus are Pane's own panels** (`PaneMenu`), never `NSMenu`, which can't be shown or captured while Pane is in the background. The menu bar keeps native items with the same commands.
- **Tools share one pattern:** the toolbar swaps to a pill with the tool's name and Done; clicks, scrolls, keys and frame buttons stay in Pane; Esc or Done ends it; one tool at a time.
- **One window per emulator.** Closing the last window quits Pane and leaves emulators running.
- **Destructive confirmations:** Cancel is the primary and the default; the destructive action is the secondary style.
- **Repo:** public, GPL-3.0, like Drop. A Swift package with no Xcode project, Swift 6, macOS 15+.
- **Code generation:** a pinned `protoc` release downloaded into a gitignored folder; the generated Swift is committed. No Homebrew install.

## How it works

- **Discovery:** each running emulator writes `~/Library/Caches/TemporaryItems/avd/running/pid_<pid>.ini` with `grpc.port` and `grpc.token`. Pane watches that folder (FSEvents, no polling) and authenticates with `authorization: Bearer <token>`. gRPC is on by default since emulator 37.2.13.
- **Frames:** `streamScreenshot` in RGBA at the view's pixel size (both width and height set, or it ignores scaling), restarted only on resize (debounced) or rotation. The emulator sends a frame only when the screen changes. Metal wasn't needed (42 to 59 fps while scrolling).
- **Rotation:** the physical model's z angle, as Android Studio does. The emulator eases the angle, so a turn can briefly report another orientation; Pane follows only the one it asked for.
- **Input:** one long-lived `streamInputEvent` call for mouse, touch, scroll and keys. Window points map to device pixels through the drawn screen rectangle and the rotation. A release is always sent when the pointer leaves or the window loses focus, so no touch sticks.
- **Unsandboxed:** the App Sandbox blocks the discovery folder.

## "Show All Emulators in Pane"

Every emulator launch opens in Pane when this is on (Settings). `scripts/emulator-takeover.sh` installs:

- a shadow SDK at `~/Library/Android/pane-sdk` (symlinks to the real SDK; its `emulator` launcher is a wrapper);
- a marked block in `~/.config/fish/config.fish`, `~/.zprofile` and `~/.zshrc` pointing `ANDROID_HOME`, `ANDROID_SDK_ROOT` and the emulator on PATH at it.

The wrapper adds only `-no-window` to AVD launches (`-avd`, `@name`), opens Pane in the background on that AVD (`pane://attach?avd=`, and `--attach` for a fresh launch), passes other calls through, runs the real emulator unchanged when Pane is missing (or `PANE_TAKEOVER=0`), re-syncs its links after SDK updates, and `exec`s the real launcher. Expo finds the emulator as `$ANDROID_HOME/emulator/emulator`, else `emulator` on PATH, and starts it with `@<name>`.

- **The shadow path has no spaces:** an SDK path with spaces breaks the NDK's tools, and Splito builds native code.
- **The fish block is at the end of `config.fish`,** not in `conf.d`: fish runs `conf.d` first, and `config.fish` sets the real SDK. **The zsh blocks are in `.zprofile`** (after its own Android lines, for login shells) **and `.zshrc`** (interactive shells that inherited the real SDK).
- **Caveats:** `sdkmanager` run from a shell with the shadow set writes new top-level folders into the shadow, and an emulator update through it would replace the wrapper folder. Update the SDK from Android Studio, or pass `--sdk_root`. Pane must stay at the path it was installed from; turn the switch off and on after moving it.
- **On other people's Macs:** off by default, never turned on or re-enabled by Pane or by an update.
- **Not handled yet:** bash (only fish and zsh); re-running install when an update brings a newer script than the installed wrapper.

## Risks

- Raw frames are large (10.4 MB full size). Pane asks for the view's size: full-size frames double the latency and data and Pane drops frames (measured 2026-11-17).
- The proto can change between emulator versions: the copied protos are pinned and the emulator version is checked at runtime.
- Auth may move to JWT only; the key-file route is the fallback.
- Emulator 37.2.13 crashes under any screen stream (`AGENTS.md`, "The emulator build").

## Not in v1

Command shortcuts other than paste (copy, cut, select all) aren't forwarded to Android; no multi-touch (pinch); no physical phones.
