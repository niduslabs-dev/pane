# Pane

A Mac app that mirrors an Android emulator in a clean window, inside a device frame we draw, and forwards clicks, scrolls, keys and frame-button presses to it over the emulator's own gRPC interface (`EmulatorController`). It also starts emulators headless. Android emulator only. Status: v1 and the tools (More menu, Open link, Inspect layout, Measure, Pick colour, emulator switcher, one window per emulator) built 2026-11-17, waiting for Jatin to try them.

- Plan and decisions: `../plans/pane.md` (Nidus Labs workspace). Research with sources: `~/Work/personal/.claude/research/emulator-mirror-grpc.md`.
- Design canvas: [Pane design](https://claude.ai/artifact/SSy48PyDrNEapFzTWwoybJ). Studio design rules: `../docs/mac-app-design.md`.

## Layout

A Swift package, no Xcode project. Swift 6, strict concurrency, macOS 15+.

- `PaneCore` (no UI, all unit-tested):
  - `Discovery/`: running emulators from `~/Library/Caches/TemporaryItems/avd/running/pid_*.ini` (port, token, AVD) with a folder watcher; AVDs from `~/.android/avd`; the SDK's emulator binary; each AVD's `config.ini` (model, Android version, screen, density).
  - `Launcher/`: starts an AVD headless through `Process` and stops emulators by PID.
  - `Client/`: `EmulatorConnection` (plaintext HTTP/2 gRPC with the bearer token: `streamScreenshot` in RGBA with both sides set, one long-lived `streamInputEvent`, status, rotate, PNG screenshot) and the reconnect backoff.
  - `Geometry/`: the frame layout for any size and the four orientations, window points to device pixels, the Window menu sizes.
  - `Input/`: key mapping (W3C names, typed text) and scrolling as a touch drag (phone AVDs have no wheel device, so `WheelEvent`s are dropped).
  - `Capture/`: file names like macOS's own, the save folder (`CaptureLocation`: macOS's screenshot `location`, else the Desktop), `FrameRecorder` (H.264 `.mov` from the frames, variable frame rate), `GifExporter` (a recording as a GIF, ImageIO) and `FramedScreenshot` (Pane's frame drawn around a screenshot on a clear background).
  - `Transfer/`: `DropPlan` (dropped files: `.apk` installs, the rest copy to `/sdcard/Download`, media is scanned) and `Adb` (the real SDK's adb through `Process`, serial `emulator-<console port>`, errors cut to one line). `Adb.run(_:timeout:)` runs any argument array and returns the output; `adb shell` joins its arguments for the device's shell, so quote typed text with `deviceShellQuoted`.
  - `Tools/`: `DeviceLink` (Open link: validation, the `am start` arguments, adb's failure in one line) and `RecentLinks`; `DeviceAppearance`, `DeviceTextSize`, `DeviceLocation`; `LayoutTree` (the `uiautomator dump` parser, hit-testing, parent frames), `DensityScale` (px × 160 / density), `EdgeDistances`, `ScreenScale`; `MeasuredLine` and `SnapEdges`; `PickedColour` and `PixelGrid`.
  - `Windows/`: `WindowRoster` (one window per emulator, where an attach request goes) and `SwitcherEntry` (the switcher's rows).
  - `Clipboard/`: `ClipboardSync`, the rules for text moving between the Mac's clipboard and the device's (gRPC `setClipboard`, `getClipboard`, `streamClipboard`).
  - `Takeover/`: "Show All Emulators in Pane" state and runner, and `AttachRequest` (`pane://attach?avd=` and `--attach <avd>`).
  - `Generated/`: protoc output, committed.
- `Pane`: the app.
  - `Theme.swift` holds every size and colour (menus in `Theme.Menu`, the tool pill in `Theme.ModePill`, tool drawing in `Theme.Tools`, tool colours `Palette.tool…`).
  - `main.swift`: `AppDelegate` (the windows, one `PaneWindowController` each, the roster, attach requests, the `pane://check-…` URLs), `PaneWindow` and the More toolbar item.
  - `PaneWindowController`: one window and its `PaneModel`; the window delegate; runs `DeviceCommand`s; opens the menu panels and sheets; remembers each emulator's window position.
  - `PaneModel` owns the connection, the emulator Pane started, sizes, recording and the input rules; `PaneModel+Device.swift` has screenshots, GIF export, Open link and the device's appearance, text size and location.
  - `PaneSettings`: everything remembered between launches, in one observable type (the Settings window binds to it).
  - `MenuPanel.swift`: Pane's own menus (`PaneMenu` holds the rows and the keys, `PaneMenuPanel` draws them). More, the emulator switcher and the emulators menu use it; never `NSMenu`, which also can't be shown or captured while Pane is in the background. `DeviceMenu.swift` builds their rows and the menu bar's native items from the same `DeviceCommand`s.
  - `Tools/`: `ToolsModel` (Inspect layout, Measure, Pick colour: one at a time, the screen's pointer is theirs while one is on) and `ToolOverlays.swift` (what they draw, the mode pill, the notice line).
  - `Sheets.swift`: the sheet scaffold, Open link, Set location, `ConfirmSheet` (Restart and Shut Down for an emulator Pane didn't start, with Cancel the default) and the Export GIF sheet.
  - `Kit/`: the Nidus component kit, Drop's, unchanged: tokens in `Kit` (`Kit.swift`), `Controls.swift` (button, switch and field styles, Tab-focusable even with macOS Keyboard navigation off, `FocusVisibility`), `Select.swift` (`NidusSelect`, its own menu in a child panel), `KitComponents.swift` (the panel card, window backdrops, `RowCard`, `SettingsRow`, `SwitchRow`, `PopupPanel`, `FrameSlide`, `WindowPresence`), `Motion.swift`. Settings and the update surfaces draw with `Kit`; the emulator window keeps `Theme`. To take a kit change, copy it from Drop, never edit here alone.
  - `Settings/`: `SettingsView.swift` (board 14: the page, `SettingsWindowController`, Save to's choices) and `TakeoverSwitch` (Show all emulators in Pane: changing and failed states around the script).
  - `Updates/`: besides the engine (below), `UpdateViews.swift` (the popup, the Settings banner, `UpdatePopupController`, which is the `UpdateSurface`) and `UpdateCopy.swift` (every string the surfaces show, tested).
  - `Chrome.swift` is the title bar (the device name is the switcher's button) and the toolbar under the device; `StateViews.swift` holds the no-emulator, progress and can't-connect screens; `PaneContentView` lays out the frame; `MainMenu` is the menu bar.
- `Resources/AppIcon.icns`: the app icon, from the assets repo (`../assets/apps/pane/`); refresh with `scripts/sync-icon.sh`, never edit it by hand. `build-app.sh` bundles it, and the update surfaces draw it from the bundle (`PaneIcon`).
- `Protos/`: the vendored proto and the emulator version it came from.
- `Resources/Assets.xcassets`: Pane's custom symbols (`pane.home`, `pane.rotate.left`), generated by `scripts/make-symbols.py` from measurements of Device Hub's toolbar (never Apple's artwork) and compiled by `build-app.sh` with `actool`. Edit the script, not the SVGs.
- `scripts/emulator-takeover.sh install|uninstall|status`: the shadow SDK at `~/Library/Android/pane-sdk` (no spaces: the NDK breaks on them) whose `emulator` is a wrapper (adds `-no-window` to AVD launches and opens Pane on that AVD), plus a marked block in `~/.config/fish/config.fish`, `~/.zprofile` and `~/.zshrc` (backed up first). Bundled into the app for the menu item; env overrides (`PANE_REAL_SDK`, `PANE_SHADOW_SDK`, `PANE_FISH_CONFIG`, `PANE_ZSH_CONFIGS`) let checks run it on scratch copies. Pane itself always launches from the real SDK.

## Design

- Chrome measured from Apple's Device Hub with the Accessibility API (title 28 pt past the traffic lights, 36 pt glass capsule and circle under the device). Boards: the [Pane design](https://claude.ai/artifact/SSy48PyDrNEapFzTWwoybJ) canvas (window boards 1 to 6, tools 7 to 13, kit 16).
- **Tools are built to boards 7 to 11 and 13.** Tool colours are fixed in both modes because they draw on the device: moss `#4F7A4A` for outlines and lines, amber `#B25E00` (always dashed) for distances and snap guides, a paper halo around both, ink chips. Pick colour's loupe reads the frame Pane is showing (scaled down in a window smaller than the device); a click takes a full-resolution screenshot (`EmulatorConnection.screenshotFrame`) and copies the device's own pixel.
- **The window is glass in light mode too** (a deviation, below). Paper tint 93% and ink tint 86% keep secondary text at 4.5:1 over pure black or white (`GlassTests` holds it); Reduce Transparency and Increase Contrast make it solid.
- **Settings and updates are built to boards 14 and 15** with Drop's kit: Settings is white in light and ink glass in dark (solid with Reduce Transparency or Increase Contrast), 560 wide, centred, as tall as its page up to 720. The update popup is the top-right notification panel and never takes focus.
- **Increase Contrast:** every dynamic colour resolves through `ColourLook`, which also reads the system setting, because SwiftUI resolves `Color(nsColor:)` with a plain light or dark appearance. Hairlines go through `Hairline` / `Kit.hairlineWidth` (1 pt under Increase Contrast). Every hosting root ends in `.displayOptions()`, which carries the debug flags into SwiftUI's environment.
- **Disabled is `opacity.disabled` (0.45), applied once.** Borderless buttons use `.plainRow` (`PlainRowButtonStyle`), never `.plain`, which dims a disabled label again on its own.
- **Every confirmation is a Nidus sheet** (`ConfirmSheet`, `SheetPresenter`), never `NSAlert`. Destructive ones (Restart emulator, Shut down emulator, for an emulator Pane didn't start) make Cancel the moss primary, rightmost and the default (Return), and the action a secondary capsule (Button's destructive variant; decided by Jatin 2026-11-17). Others make the action the moss primary and the default. Esc always cancels.
- `scripts/build-app.sh` stamps the real SDK version into the binary with `vtool`. SwiftPM records the deployment target there, which makes AppKit draw the pre-macOS 26 look (12 pt traffic lights, no glass toolbar items).

## Design deviations

Everything Pane does that is not on a board or differs from the kit (`../docs/design-language.md`, "Staying inside the language"). Each line: what (the token or contract, Pane's value), why, decided by, date.

- **Light window is glass, not solid paper** (`surfaceBase`; paper tint 93% over a behind-window blur). Why: Jatin's choice of look. Decided by Jatin, 2026-11-17 (`../plans/pane.md`). Approved.
- **Start emulators without sound is on by default** (board 14 draws it off). Why: Pane always passed `-no-audio`, so on keeps today's behaviour. Proposed by the build agent. Approved by Jatin, 2026-11-17.
- **The inspect card has a Label row** when the view has text (board 9 has none). Why: the text is how you find the view again. Proposed by the build agent. Approved by Jatin, 2026-11-17.
- **The inspect card moves out of the way** (board 9 draws it under the outline): under the outline, else above it, else at the screen's bottom or top. Each distance chip stays beside its guide (under a level one, right of an upright one) and slides only along it, overhanging the guide's outer end on a short guide; a chip that fits nowhere on its guide drops "px", then hides, rather than leave its guide (`LabelPlacement.placeOnGuide`). So nothing covers another label or the outline. Why: review 2 found chips and the card on top of each other; review 2 round 2 found chips moved off their guides. Proposed by the review-fix agent. Approved by Jatin, 2026-11-17 (chips back on their guides, 2026-11-17).
- **Location's first choice is "Default", not "None"** (board 7), and the Set location sheet says "until you choose Default." Why: the choice puts the GPS back at the emulator's own default, which None didn't say. Proposed in commit 655b887. Approved by Jatin, 2026-11-17.
- **Version row, builds that can't update** (board 15 has no such state): the caption says "This build doesn't update itself." and Check for Updates stays disabled in place. Why: debug and ad hoc builds carry no feed or key, so a check can't run. Proposed by the build agent. Approved by Jatin, 2026-11-17.
- **Version row, a spinner before "Checking…"** (board 15 shows the words only). Why: a check can take a few seconds and the words alone look stuck. Proposed by the build agent. Approved by Jatin, 2026-11-17.
- **Export Recording as GIF confirms in a Nidus sheet** (no board; `Sheet` / Confirmation): title "Export recording as GIF", "The GIF is saved next to the recording.", a card row with the recording's name and a small "Choose Another…", then Cancel and a moss Export. Export is not destructive, so Return runs it; Esc cancels. Why: it replaced a system alert with three equal buttons. Proposed by the review-fix agent. Approved by Jatin, 2026-11-17.
- **Destructive sheet buttons have no trash icon** (Button's destructive variant draws one): Restart emulator and Shut down emulator delete nothing, so a trash would say the wrong thing. Proposed by the kit-sync agent, 2026-11-17. Not yet approved by Jatin.
- **Menus, the ⓘ popover and the inspect card blur within the window** (`inkGlass` says a behind-window `.hudWindow` blur): `surfaceMenu` dark (and `tool.chip`) over a within-window `.hudWindow` blur, solid under Reduce Transparency or Increase Contrast. Why: they are drawn inside Pane's window over the device, so a behind-window blur would blur the desktop and leave the device's text sharp under them. Proposed by the review-fix agent. Approved by Jatin, 2026-11-17.

Not deviations, for the next review: the Save to select's fill is paper (`#F4F4F6`, `surfaceRaised` in `tokens.kit.json`; settled by Jatin 2026-11-17, board 14 to follow), and its menu (tick on the right, soft open ring, width = max(select, content), no divider) follows the Select contract. The switcher's Open in new window submenu is on board 13 (the "Open in new window" figure), placed under its row as drawn there.

## Commands

Homebrew's LLVM env breaks Xcode builds, so build through `scripts/swift.sh`, which clears it:

```sh
scripts/swift.sh build
scripts/swift.sh test
scripts/build-app.sh [--debug]     # build/Pane.app, ad hoc signed
scripts/format.sh                   # swift format; --lint for the strict check
scripts/generate-protos.sh          # regenerate Sources/PaneCore/Generated (pinned protoc in .claude/tools)
```

**Checking the app without taking focus** (`.claude/checks/`, gitignored; `lib.sh` wraps the common steps):
- `relaunch.sh [args]` quits the Pane it started (menu Quit, then SIGTERM) and opens a new one with `open -g`; `-NSRequiresAquaSystemAppearance YES` for light.
- `window-info.swift <pid>` finds the window; capture with `screencapture -l <id> -o -x`.
- Input posted to the PID, window-local points, nothing activates: `click` (with hold or drag), `move.swift` (pointer moves), `scroll.swift`, `key.swift`.
- Accessibility: `axpress.swift <pid> <title> [--menu]` presses a button or menu item (a trailing `*` matches a prefix); `axdump.swift` prints the tree with bounds; `axsize.swift` resizes.
- `movinfo.swift` checks a recording; `pixels.swift` and `contrast.py` sample colours.
- Debug-build flags: `-PaneCaptureFolder <dir>` (screenshots and recordings never go to the Desktop in checks), `-PaneReduceTransparency YES`, `-PaneIncreaseContrast YES`, `-PaneAVDHome <dir>` (fixture AVDs in `.claude/checks/fixture-avd`), `-PaneNoAutoAttach YES` (keeps the no-emulator screen up), `-PaneScreenCaptureLocation <value>` (stands in for macOS's screenshot setting; never change the real one), `-PaneRegistrationFolder <dir>` (fake emulators: `.claude/checks/fake-sdk` registers on a dead port, run with `open --env ANDROID_HOME=…`).
- Drops and paste can't be posted to a background window, so the debug build takes `pane://check-hover?file=…`, `check-hover-end`, `check-drop?file=…` and `check-paste` (same handlers), plus `-PaneTreatAsKey YES` and `-PanePasteboard <name>` (a private pasteboard; `pb.swift <name> [text]` reads or writes it), so checks never touch the real clipboard. `uidump.py` prints the device's text nodes.
- `build-debug.sh` builds the debug copy straight into `.claude/checks/debug` (`PANE_APP=<path> scripts/build-app.sh`), so the copy running from `build/` is never replaced under Jatin. `v2.sh` wraps the debug copy's steps (`drun`, `dquit`, `dshot`, `dmenu`, `dpress`, `dclick`, `dmove`, `dkey`, `durl`, `dlog`); `axmenus.swift` prints the menu bar with shortcuts and ticks, `axclose.swift` closes a window, `pbtypes.swift` shows what is on the private pasteboard.
- More debug URLs: `check-open-link?text=…` and `check-location?lat=…&lon=…` (the sheets, prefilled; press their buttons through Accessibility), `check-gif?file=…`, `check-switcher`. Menu panels take posted keys (`key.swift --code 125` is Down, 124 Right, 36 Return, 53 Esc) and a posted click on the title opens the switcher.
- Settings and updates: `-PaneBackgroundCheck YES` opens every window behind the others without activating Pane (the popup too, at the normal level); `-PaneTakeoverCheck ok|changing|failed` stands in for the takeover script (always pass it in a check: the real switch edits the shell setup); `-PaneSlowStartAfter <seconds>` shortens the slow-start wait. URLs: `check-settings`, `check-update?state=ready|later|available|downloading|checking|uptodate|failed`, `check-select?label=Save%20to`, `check-save-folder?path=…`, `check-drop-error`, `check-drop-details`, `check-restart`, `check-shutdown`, `check-export-gif?file=…`, `check-more` (More's menu). Under `-PaneTakeoverCheck` the stand-in's shell setup starts off (`-PaneTakeoverInstalled YES` for on), so a check turns the switch on as board 14 draws it. `PANE_BUNDLE_ID=<id> scripts/build-app.sh` gives a check's copy its own preferences. Send URLs with `open -g -a <that copy> <url>`, since every Pane copy claims `pane://`.
- `update-e2e.sh` runs the real Sparkle path against a local appcast with a throwaway key (never the release key): a fake 0.9.1 DMG, a 0.9.0 debug copy with `-PaneUpdateFeed`, automatic on and off, then install on quit.
- `debug-run.sh` / `debug-quit.sh` run a separate debug copy (`.claude/checks/debug/`) by PID, leaving Jatin's release copy alone; `windows-of.swift <pid>` lists a process's windows (a headless emulator has none).
- `soak/` reproduces the emulator crash and checks a build against it: `run-soak.sh <label> <seconds> -- --size 737x1638` (the `streamsoak` client, built with `scripts/swift.sh build -c release` in `soak/streamsoak`, plus `drive.sh`, an adb loop that opens, rotates and force-stops apps), `pane-soak.sh <label> <seconds> [copies]` (a private debug copy going through the size modes), `start-emu.sh` / `stop-emu.sh` (`EMU_BIN`, `EMU_FLAGS` pick another emulator build or flags), `vanish.sh` (quitting and killing Pane copies never stops the emulator). Results go to `.claude/screens/v2-fixes/`.
- The debug build logs at debug level under subsystem `dev.niduslabs.pane`; `log show` skips debug lines, so use `log stream --level debug`.

## Conventions

- **Never log or print the gRPC token.** `GRPCToken` redacts every textual form; only the `authorization` header sees it.
- **Every press ends in a release:** mouse up, drag off the screen, pointer exit, window or app losing focus. Held keys and a wheel's scrolling finger too.
- **Pane only stops emulators it started** (by PID); restarting any other asks first in a sheet. Stop on a slow start stops only the process Pane launched.
- **Errors are plain sentences.** adb's own reason goes behind Details (`Adb.plainError`, `Adb.reason`), never on the status line.
- **Never log clipboard contents,** only that text moved. **The clipboard moves only while Pane's window is key:** text copied elsewhere on the Mac reaches the device only when pasted (Command-V) into Pane.
- **Pane never starts an emulator on its own:** only Start and Restart do (both logged). One stopped from outside (`adb emu kill`) shows Start.
- **Dependencies pinned with `exact:`** and `Package.resolved` committed. gRPC Swift 2 needs macOS 15.
- **Generated code is committed and never edited.** To update: copy the new proto into `Protos/`, note its emulator version there, run `scripts/generate-protos.sh`.
- **Theme constants only;** views hold no raw numbers. Format and lint with Apple's `swift format` (`.swift-format`, lint `--strict` clean); generated code is excluded.
- **Unsandboxed:** the App Sandbox blocks the registration folder.
- **While a tool is on, nothing reaches the device:** clicks, scrolls, keys and frame buttons are the tool's. Esc or Done ends it.
- **One window per emulator.** Asking for an emulator a window already shows brings that window forward. Closing the last window quits Pane and leaves emulators running.
- **The title bar takes clicks before SwiftUI content under it,** so `PaneWindow.sendEvent` hands a click on the device name to the switcher, and the model tracks the pointer over it for the hover shade.
- **Menu bar shortcuts** (the panels show the same): Open Link ⌘L, Save Screenshot ⌘S, Copy Screenshot ⇧⌘C, Inspect Layout ⌥⌘I, Measure ⌥⌘M, Pick Colour ⌥⌘P, New Window ⌘N.
- **One agent drives the emulator at a time** (shared device, see the workspace guide).

## The emulator build

Write-up with the evidence: `~/Work/personal/.claude/research/pane-emulator-crashes.md`.

- **Emulator 37.2.13 (stable) crashes while anything streams its screen and an app closes.** Each `streamScreenshot` frame is read back on the emulator's PostWorker thread through a GL context that exiting app render threads also use, with no lock (gfxstream); Metal then aborts ("A command encoder is already encoding to this command buffer"). One stream is enough, scaled or full size; Android Studio's embedded view takes the same path. Pane can't avoid it from its side.
- **This Mac runs the beta emulator, 37.3.9 (build 16863232),** installed into the real SDK on 2026-11-17 (Jatin's decision) with `sdkmanager --sdk_root=$HOME/Library/Android/sdk --channel=1 emulator`. It ran the same soaks clean (10 minutes each with the bare client, one Pane window and two Pane copies; 37.2.13 died in 5 of 5 such runs). Don't go back to 37.2.13, and soak a newer build (`soak/`) before trusting it.
- **Rolling back:** download Google's stable archive (`https://dl.google.com/android/repository/emulator-darwin_aarch64-16740729.zip`, SHA-1 `6c5e61b873e11c7d1d08683bea089f762baee070`), stop the emulator, move the SDK's `emulator` folder **out of the SDK** and unpack the archive's `emulator` folder in its place, then run `scripts/emulator-takeover.sh status`. Never leave a renamed emulator folder inside the SDK: `sdkmanager` takes it for the installed package and upgrades it in place (that is how the first backup was lost).
- **Pane keeps asking for frames at the window's size.** Full-size frames take the same path in the emulator, double the latency and data, and drop frames in Pane (measured in a debug build: 14 ms and 1 dropped frame at Fit Screen, 33 ms and 720 dropped frames in 79 busy seconds at Pixel Accurate, which asks for full size).
- **An emulator Pane starts writes its output to `~/Library/Logs/Pane/emulator-<avd>.log`** (the launch before it is `.previous.log`). A graphics crash prints its reason there and nowhere else.
- **Quitting or killing a Pane copy never stops an emulator,** also not the copy that started it (`soak/vanish.sh`): the emulator runs in its own process group and is re-parented to launchd.
- **When the emulator ends, Pane's log tells how:** `Stream unexpectedly closed` is a crash (look in `~/Library/Logs/DiagnosticReports/qemu-system-aarch64*.ips`), `Cancelling all calls` is an orderly shutdown that something asked for.

## Updates and releasing (not released yet)

Plan, open questions and the credential steps: `../plans/pane-ship.md`. Mirrors Drop (`../drop/AGENTS.md`, Releasing).

- **Updates:** Sparkle (pinned `exact:`) with Pane's own surfaces, never Sparkle's windows. `Sources/Pane/Updates/UpdateModel.swift` is the state machine (no Sparkle types; `PaneTests/UpdateModelTests` drive it with a fake feed), `UpdateDriver.swift` maps Sparkle's callbacks to it, and `UpdatePopupController` is the `UpdateSurface`: the popup shows an update that is ready or waits for Download, and follows a download started from its own button. Everything else (a check by hand, its result, a download it started) shows in Settings' Version row, which reads the model. "Check for Updates…" in the app menu opens Settings at the Pane group and runs the check. Later keeps the update: it installs when Pane quits, and Settings shows the banner until then.
- **Only Developer ID builds update.** `build-app.sh` writes `SUFeedURL` and `SUPublicEDKey` only for a real `SIGN_IDENTITY` (or when `SPARKLE_PUBLIC_KEY` is passed for a test), and the app starts Sparkle only when both are there. Debug builds never do, except with `-PaneUpdateFeed <url>` (a local test appcast).
- **Releases** are built only by `.github/workflows/release.yml` (tag `vX.Y.Z` or by hand): lint, test, `build-app.sh` (env `VERSION`, `BUILD`, `SIGN_IDENTITY`), `scripts/package-dmg.sh <version>` (DMG; signs, notarizes and staples when its env is set), `sign_update`, `scripts/appcast.sh`, then a GitHub release with the DMG and `appcast.xml`. Notes come from the version's section in `RELEASE_NOTES.md`. Nothing is signed or notarized from a laptop.
- **Secrets** belong to the `release` environment and are set by Jatin only. `scripts/new-update-key.sh` makes the update-signing key; agents never run it.
