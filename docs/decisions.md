# Pane: how it works and why

The decisions behind Pane and how the mirror works. Moved here from the workspace plan (`studio/pane/plan.md`, deleted 2026-11-19 once Pane shipped; git keeps it). `AGENTS.md` is the map of the code and the rules; this file is the reasoning. Research with sources: `~/Work/personal/.claude/research/emulator-mirror-grpc.md`.

## Goal

A small Mac app that mirrors a running Android emulator in a clean window, inside a device frame we draw ourselves, and forwards clicks, scrolls and keys to it. It replaces the emulator's own window (grey title bar, separate side toolbar) for day-to-day work.

## Decisions (2026-11-16 and 2026-11-17)

- **Android emulator only.** No physical phones (that would need scrcpy's protocol), no iOS Simulator (private Apple frameworks).
- **Transport:** the emulator's own gRPC interface (`EmulatorController`), straight from Swift with gRPC Swift 2. No helper process for the stream. WebRTC isn't in the macOS emulator build.
- **Frame:** our own, drawn from the device's screen size (body, bezel, side buttons), so it fits any emulator. Android draws the camera cutout into the frames it streams and screenshots; Pane draws none (board 26, approved 2026-11-22). Google's Pixel skins aren't bundled or downloaded: their licence is stated only in a sibling file's header, and "Pixel" is a trademark.
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
- **Live screen size (board 27, 2026-11-22):** the window always has the shape of the screen Android shows. Each frame's `ImageFormat.foldedDisplay` (exact pixels, portrait) wins over `config.ini`'s `hw.lcd`; `getDisplayConfigurations` never changes on a fold and `wm size` overrides change neither stream nor touch, so neither is followed. A frame of another size or orientation than the stream was asked for is dropped and starts the reshape. Each AVD's last folded shape is remembered (`liveScreenSize.<avd>`), so a folded Fold opens folded. Research: `.claude/research/fold-stretch.md`.
- **Reshape:** held touches are released and clicks wait; the last frame is blurred (`revealBlur`, 8 pt) and dimmed (`scrim`) as a layer filter on the screen, filling it cropped and centred, while `WindowMorph` steps the window and an interpolated `DeviceFrameLayout` on `slideIn` from a display link (top edge and centre held, clamped to the display) and the stream restarts at the new size. The new frame waits under the veil until the morph settles (`ReshapeTransition`), then the veil eases out over `fade`. A turn from Pane's button starts on the click and fades the side buttons. Reduce Motion: new size at once, then a 200 ms crossfade. Pane keeps the height the user chose and shows max(chosen, the shape's minimum), so forced raises never stick.
- **Rotation:** the physical model's z angle, as Android Studio does. The emulator eases the angle, so a turn can briefly report another orientation; Pane follows only the one it asked for.
- **Input:** one long-lived `streamInputEvent` call for mouse, touch, scroll and keys. Window points map to device pixels through the drawn screen rectangle and the rotation. A release is always sent when the pointer leaves or the window loses focus, so no touch sticks.
- **Unsandboxed:** the App Sandbox blocks the discovery folder.

## "Show All Emulators in Pane"

Every emulator launched from the SDK Pane wraps runs headless and opens in Pane when this is on (Settings). Plan, spike results and sources: the workspace's `studio/pane/takeover.md` (approved by Jatin 2026-11-22; boards 23 and 25). It replaced 1.0's shadow SDK, which reached only shells started after install, let `sdkmanager` write into it, broke on updates through it and fixed Pane's path.

- **The wrapper sits in the real SDK** (`Sources/PaneTakeover/TakeoverWrapper.swift`): `<sdk>/emulator/emulator` becomes a script and the real launcher is `emulator-real` beside it. An AVD launch (`@name`, `-avd name`) asks Pane to show it (`open -g -b <Pane's bundle id> pane://attach?avd=… --args --attach …`, which starts Pane in the background when it isn't running) and `exec`s the real launcher with `-no-window` (before any `-qemu`). `-no-window`, `-qt-hide-window` (Studio's tool window), info calls and `PANE_TAKEOVER=0` pass through and never open Pane. When `open` fails (Pane in the Trash) the emulator runs as without Pane, window and all. No path is baked in, so Pane can move.
- **Expo and RN CLI** run `$ANDROID_HOME/emulator/emulator @<avd>` with `spawn`, no shell: the kernel runs the script, and `exec` keeps the PID, so Expo's "quit before it opened" check holds (checked with Expo's exact call on a scratch SDK, 2026-11-22).
- **On means the user's choice,** saved with the SDK's real path (`PaneSettings.takeoverSDKPath`), never "the wrapper is there now". The SDK is resolved once when the switch turns on: `PANE_REAL_SDK` (checks), else the login shell's `ANDROID_HOME`/`ANDROID_SDK_ROOT` (`$SHELL -l -i -c`, since Pane opened from the Dock or by the wrapper has launchd's environment), else Pane's own lookup.
- **An emulator update replaces `sdk/emulator` whole** (sdkmanager and Studio share `BasicInstaller`: unpack while `emulator/.installer` exists, rename to `emulator.backup`, rename the new folder in, write `package.xml`, delete the backup), so the wrapper goes with it. **One repair** (`TakeoverRepair.wrap`) puts it back: it waits for no `.installer`, no `emulator.backup`, a `package.xml` and 2 s of quiet; holds a `flock` (`~/Library/Caches/dev.niduslabs.pane/takeover-repair.lock`); works through one directory handle (`linkat`, `openat`, `renameat`), so a folder swapped mid-repair takes the whole repair with it; hard-links `emulator` to `emulator-real`, then renames the wrapper over `emulator`, so a launcher always exists; leaves a script that isn't Pane's alone; and is a no-op when already wrapped.
- **Who repairs:** Pane on launch and on every change to the SDK's root folder while it runs (`SDKFolderWatcher`), and a launch agent when Pane isn't running: `~/Library/LaunchAgents/<bundle id>.takeover-repair.plist` runs `Pane Emulator --repair <sdk> --bundle-id <id>` on `WatchPaths` = `<sdk>/emulator` (launchd keeps watching across the folder swap; it must be the real path, not a symlink). It is a per-user plist, not an `SMAppService` agent, because a bundled plist is fixed and the SDK can be anywhere. `AssociatedBundleIdentifiers` names Pane in macOS's notice and in Login Items. Pane rewrites the plist only when its contents change (the helper's path after a move, another SDK) and reloads it when launchd doesn't have it. Its output goes to `~/Library/Logs/Pane/takeover-repair.log`.
- **Pane's own launches skip the wrapper** (`AndroidSDK.launchable`: `emulator-real` when it's there), or Pane would ask itself to attach.
- **Background item turned off** in System Settings: `SMAppService.statusForLegacyPlist(at:)` says `.requiresApproval` (it says `.enabled` for a tracked legacy agent that's on, verified on this Mac's agents; the off case is from the documentation, not seen live). Settings then says repairs are off, with Open Login Items. Pane still repairs on launch.
- **"Background Items Added" shows only the first time:** macOS doesn't show it for the repair agent when Pane already has a Background Task Management record (Jatin turned the switch on in 1.1.0 on 2026-11-22: no notice, and the agent works). Board 25 draws the notice for a first-time install only.
- **Off** unloads and deletes the agent and renames `emulator-real` back over the wrapper (one atomic step).
- **Moving from 1.0:** the first launch that finds the shadow SDK or its shell blocks runs the old uninstall (`scripts/emulator-takeover.sh uninstall`, bundled, which backs up each config first) and, when the old switch was fully on, turns the new one on. If the uninstall fails the new switch stays off and Settings says so the next time it opens.
- **Leftovers:** Pane dragged to the Trash leaves the wrapper (it runs the real launcher, since `open -b` fails) and the agent (its job fails quietly). Clean up by putting Pane back and turning the switch off, or by hand: `launchctl bootout gui/$(id -u)/dev.niduslabs.pane.takeover-repair`, delete that plist, and `mv <sdk>/emulator/emulator-real <sdk>/emulator/emulator`. An emulator update also clears the wrapper.
- **Debug builds refuse the real work** unless `PANE_REAL_SDK` and `PANE_LAUNCH_AGENTS` point at scratch folders (and run the 1.0 migration only with `PANE_SHADOW_SDK` set), so a debug copy never wraps the real SDK.
- **On other people's Macs:** off by default, never turned on by Pane or by an update, except to carry 1.0's switch forward.

## Risks

- Raw frames are large (10.4 MB full size). Pane asks for the view's size: full-size frames double the latency and data and Pane drops frames (measured 2026-11-17).
- The proto can change between emulator versions: the copied protos are pinned and the emulator version is checked at runtime.
- Auth may move to JWT only; the key-file route is the fallback.
- Emulator 37.2.13 crashes under any screen stream (`AGENTS.md`, "The emulator build").

## Not in v1

Command shortcuts other than paste (copy, cut, select all) aren't forwarded to Android; no multi-touch (pinch); no physical phones.
