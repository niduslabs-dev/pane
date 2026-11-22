# Pane: tokens to add

Pane adopted the studio's generated tokens on 2026-11-17: shared values come from `Sources/Pane/Theme/ThemeTokens.swift` (`scripts/sync-tokens.sh`), and both `Theme.swift` and `Kit/Kit.swift` read it. What's left is below: Pane's own values still written in those two files. Each row is a proposal for Jatin; until he decides, the value stays where it is, named, with its reason. None is a new raw value. Moved here from the adoption plan (`studio/pane/adoption.md`, deleted 2026-11-19; git keeps the full value-by-value table).

- **Kit keeps its names.** `Kit.*` is a table of `ThemeTokens` reads plus Drop's own values, so the call sites didn't move. Renaming every call site to `ThemeTokens.*` would make Pane's kit files differ from Drop's line by line and break the both-ways sync; do it when Drop adopts the tokens.
- **Engine values stay in `Theme`** (`Theme.Timing`, `Diagnostics`, `Export`, snapping, frame and screen geometry limits, `Notice` and `Drop` durations): they are not design values. `tools/design/checks/static` on Pane finds only these, outside the theme files.

| Where | Values | Proposal |
|---|---|---|
| `Theme.Screen.actionGap`, `Capsule.startPadding` | 20, 20 | off the scale on purpose (board 3); `app.pane.size.screen.actionGap`, or move to 24 |
| `Theme.Sheet.rowPaddingV` | 9 (commented) | `app.pane.size.recentRow.paddingY`, or 8 |
| `Theme.Sheet.width` | 355 | a recorded deviation (`size.sheet.confirmationWidth` 420); `app.pane.size.sheet.width` |
| `Theme.ErrorCard.glyphSize`, `TitleButton.paddingH` 9, `chevronSize` 8, `Notice.height` 28 and its shadow, `ModePill.shadow*` | | `app.pane.size.*` and `app.pane.shadow.notice`, `shadow.modePill` |
| `Theme.Typeface.statusDetail` (11 mono), `cardTitle` (15 regular), `modePill` and `notice` (12 medium) | | type styles: `type.captionMono`, `type.sectionTitleRegular`, `type.calloutMedium` |
| `Theme.Drop.outlineWidth` 1.5, `scrimOpacity` 0.72 | | `app.pane.size.dropOutline` (or reuse `app.pane.size.chip.outline`), `app.pane.opacity.dropScrim` |
| `Theme.CaptureFlash.peakOpacity`, `colour` | 0.5, white (`#FFFFFF`, both modes) | `app.pane.opacity.captureFlash` and `app.pane.color.captureFlash` (`contracts/apps/pane/captureFlash.yaml`, 2026-11-17; colour added 2026-11-18) |
| `Kit.Motion.roll*` | Drop's values (rise 6, scale 0.8, blur 1.5, spring 0.35/0.4, stagger 0.07/0.15) | shared `motion.roll.*` tokens with Drop (`numericRoll`) |
| `Theme.Window` title-row extras (`fallbackTitleLeading` 108, `titleRowTrailingPadding` 56, `cascadeStep` 28) | | `app.pane.size.titleRow.*` |
| `Theme.Frame` geometry (edge widths, inner edge inset, button edge and corner, hit outset, button positions) and colours (`frameInnerEdge`) | | `app.pane.size.frame.*`, `app.pane.color.*` in one assets change |
| `Theme.Menu.switcherWidth` 262, `submenuWidth` 150, `switcherSubmenuWidth` 242, `lineSpacing` 1, menu positions (`moreTop`, `switcherTop`, submenu shift and drop) | | `size.menuPanel.*` for the widths; positions stay Pane's |
| `Theme.Menu.statusDot` 8, `glyphArt` 14 (the switcher's status dot and device glyph, board 20, 2026-11-18) | | `app.pane.size.statusDot` (`contracts/apps/pane/DeviceStatus.yaml`); `glyphArt` stays Pane's |
| `Theme.InfoPopover` (`width` 280, `paddingH` 14, `leading` 150, `lineSpacing` 5.4) | | `size.infoPopover.*` (Drop's is `Kit.Settings.infoWidth` 260: settle one) |
| `Theme.Tools` card, loupe and swatch sizes, `haloWidth`, shadows | | `app.pane.size.tools.*` |
| `Kit.*` Drop-only values | listed in the workspace's `studio/drop/adoption.md` | with Drop's adoption |
