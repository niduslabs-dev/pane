# Pane: releasing, the reasoning

How Pane ships and why it is set up this way. The steps and the workflow are in `AGENTS.md` ("Updates and releasing"); this file keeps the decisions and the one-time setup. Moved here from the workspace's shipping plan (`studio/pane/ship.md`, deleted 2026-11-19 after 1.0.0 to 1.0.3 shipped; git keeps it).

## Drop is the reference

Pane copies Drop's route wherever it can: Sparkle 2.10.1 pinned `exact:` behind the app's own surfaces, the same Info.plist keys, signing inside out (never `--deep`), a signed and notarized DMG, `sign_update` with the key on stdin, a one-item `appcast.xml` on the latest GitHub release, notes from `RELEASE_NOTES.md`, one `X.Y.Z` from the tag, GitHub-hosted `xcode-27` runners.

Where Pane differs, on purpose:

1. **A check the user starts always answers.** Pane shows "up to date" and errors for a check or download the user started. Its own daily check stays silent on "nothing new" and on failure, as Drop's does.
2. **Download progress** is shown when the user is waiting, and a watched download can be cancelled.
3. **Ad hoc builds never update.** `build-app.sh` writes the Sparkle keys only into a Developer ID build, and the app starts Sparkle only when they are there. Jatin runs a local build daily and the takeover wrapper points at its path; a release must not replace it behind his back. Drop doesn't have this rule yet.
4. **Secrets live in the `release` environment,** not as repo secrets. Only the job that names the environment can read them, and only `v*` tags can deploy to it.
5. **Update settings** (check automatically, interval, download automatically) live in the Settings window.

## Decided (2026-11-17)

- **Feed: GitHub Releases** (`releases/latest/download/appcast.xml`), as Drop. Publishing is one step in the release job; a niduslabs.dev feed would need a second credential and deploy, and the zone's bot settings once blocked non-browser clients. The URL is baked into every installed copy. `latest` skips prereleases, so there is no beta channel. Leaving GitHub would take a last release there that points at a new feed.
- **Runner: GitHub-hosted, never the self-hosted Macs.** GitHub advises against self-hosted runners for public repos (a fork's pull request can run code on the machine). Standard hosted runners are free for public repos, and a fresh machine per release suits a signing job. Not verified: that `xcode-27` is a standard (free) label; check Settings › Billing after a run.
- **Automatic download** on by default. **First public version** 1.0.0.
- **The app is not notarized separately from the DMG** (Drop does the same). Notarizing both would let an updated app open offline with its own stapled ticket, at twice the notary wait.

## Versioning

- One number: tag `vX.Y.Z` gives `CFBundleShortVersionString` and `CFBundleVersion` both `X.Y.Z`. Sparkle compares `CFBundleVersion` part by part, so `0.10.0` is newer than `0.9.0`.
- Local builds carry no feed.
- No build counter, no prereleases. A bad release is fixed by the next patch, never by re-tagging: installed copies only move up.

## One-time setup (done 2026-11-17)

No agent touches the keychain, exports a certificate or sees a private key; Jatin runs these. Each secret goes straight into `gh secret set`, never through a file in the repo.

- **Environment:** `release` on `niduslabs-dev/pane`, deployments limited to `v*` tags, no required reviewer, so a pushed `v*` tag releases at once.
- **Six secrets in it:** `DEVELOPER_ID_P12` and `DEVELOPER_ID_P12_PASSWORD` (only the Developer ID Application identity, exported in memory), `ASC_PRIVATE_KEY`, `ASC_KEY_ID` and `ASC_ISSUER_ID` (an App Store Connect API key with the Developer role), and `SPARKLE_ED_PRIVATE_KEY`.
- **The update key** is Pane's own, not Drop's, made by `scripts/new-update-key.sh`: it makes the Ed25519 key in memory, stores the private half as the secret and prints the public half, which is committed in `build-app.sh`. It refuses to run twice: replacing the key after a release means every installed copy rejects later updates until reinstalled by hand. It needs Homebrew's `openssl` (macOS's LibreSSL can't make Ed25519 keys).
- **Backups:** copies of every secret are kept outside git in the workspace's `creds/` folder (mode 600). To restore one, pipe its file into `gh secret set --env release`. Check names only with `gh secret list --repo niduslabs-dev/pane --env release`.
- **Repo defaults:** the workspace's `scripts/repo-defaults.sh niduslabs-dev/pane`.

When the Developer ID certificate expires, export the new identity the same way and reset both `DEVELOPER_ID_P12` secrets, in Drop's repo too.
