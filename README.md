# Codex Account Toggle

[English](README.md) · [한국어](README.ko.md)

**Switch Codex accounts from your menu bar.**

A small macOS menu-bar utility for choosing between saved Codex accounts. Built with SwiftUI and AppKit. **Experimental and demo-first; not affiliated with OpenAI.**

![English demo](docs/screenshots/demo-en.png)

## What works today

- Three synthetic accounts in demo mode, account renaming, and simulated switching/recovery.
- Korean and English UI, light/dark themes, and visible account management menus.
- Sample plan badges, weekly-only demo quota percentages, and exact reset dates/countdowns in Korea time (KST).
- Weekly-first display and optional menu-bar quota (`D` marks demo data; `~` marks an old reading).
- Core tests for credential-file validation, private file permissions, backups, recovery, dates, and translations.

The [current-account reader](docs/read-only-connection.md) is prepared and tested with synthetic responses; its production transport remains disconnected. See the [account-switcher benchmark](docs/benchmark.md) for adopted behaviors and follow-up work.

## Important limits

The default app never accesses real sign-in files or controls Codex. Usage and plans are **samples**, not live account readings. Quota windows are shown only when present in the supplied data; a five-hour limit is not assumed for every account. A quota percentage is not a token balance.

Real switching exists behind an explicit `--live` argument but is **not end-to-end validated**. It targets file-based ChatGPT credentials and the `com.openai.codex` app identifier. Keychain/auto/ephemeral credentials, API-key sign-in, Windows, production signing/notarization, and live usage collection are not supported. Do not use real sessions in development or automated testing.

## Build and try the demo

Requires macOS 13+, Swift 5.9+, and Xcode Command Line Tools. No third-party package dependencies.

On your MacBook, install Xcode Command Line Tools with `xcode-select --install` if needed. Install GitHub CLI (`gh`) and sign in with `gh auth login`, using the GitHub account that has access to this private repository. Then:

```sh
gh repo clone ChungHyup/codex-account-toggle
cd codex-account-toggle
```


```sh
swift test --disable-sandbox
bash scripts/build-app.sh
```

To install for your macOS user, copy the built app into `~/Applications` (create the folder if necessary), or keep it in `dist`:

```sh
mkdir -p "$HOME/Applications"
ditto 'dist/Codex Account Toggle.app' "$HOME/Applications/Codex Account Toggle.app"
open "$HOME/Applications/Codex Account Toggle.app"
```

Open `dist/Codex Account Toggle.app`, then click its circular-arrows menu-bar icon. Choose a demo account. The lower settings control simulates success, refused quit, or launch failure/recovery. Use each account's `…` menu to rename it.

The language follows macOS (Korean, otherwise English). The gear menu lets you choose System, 한국어, or English; reopen **Codex Account Toggle** to apply. This never requires restarting Codex. Date labels are localized while their timezone stays explicitly KST.

For deterministic visual checks:

```sh
'dist/Codex Account Toggle.app/Contents/MacOS/CodexAccountToggle' --render-preview --language=en
'dist/Codex Account Toggle.app/Contents/MacOS/CodexAccountToggle' --render-preview --language=ko --dark
```

These render synthetic data only. `--window` opens the demo in a small standalone window. Demo workspaces are created under the system temporary directory and are not committed.

For a design-only preview without demo copy, add `--product-preview` to `--render-preview`. It writes `dist/product-preview-en.png` for English (or `product-preview-dark-en.png` with `--dark`). It still uses synthetic accounts and the fake lifecycle. This flag only affects offscreen rendering; normal demo launches keep their labels. These images do not show live account data.

## Credential handling

Experimental live mode reads `CODEX_HOME/auth.json` (default `~/.codex/auth.json`) and stores snapshots under `~/Library/Application Support/CodexSwitch`. Files are plaintext with mode 0600; the directory uses 0700. This is file-permission protection, not encryption. The app itself has no telemetry or network client. Project/session/skill/config files are not intentionally modified.

Switching is designed to request a normal quit, confirm Codex processes are gone, back up the prior sign-in, replace the file, and reopen the app. Recovery is deferred when a process may still be using credentials. These file-level checks do not prove successful server authentication. See [security notes](SECURITY.md) and [implementation review](docs/review.md).

## Contributing and publication

See [CONTRIBUTING.md](CONTRIBUTING.md), [CHANGELOG.md](CHANGELOG.md), and [publication readiness](docs/publication.md). macOS CI runs synthetic tests, source checks, and the app build; check the repository’s Actions tab for hosted results.

Licensed under the [MIT License](LICENSE), copyright © 2026 Chunghyup OH. The reference project [ScWen7/CodexSwitch](https://github.com/ScWen7/CodexSwitch) is also MIT-licensed. This is a new Swift implementation; no reference source is vendored.

The app was formerly named Codex Switch. Its profile directory retains that name for compatibility; no credential migration is performed. With an old-name instance open, quit that utility yourself before opening the renamed app. The new app identifier starts with default preferences.

## Manual QA on a separate Mac

Start with the default demo. Check account names, English/Korean, light/dark appearance, weekly quota layout, and the simulated refused-quit/recovery scenarios. Live usage collection is still disconnected: real accounts will not show the sample percentages.

Only when you choose to test your own real accounts, finish your Codex work and close its CLI sessions. Quit **Codex Account Toggle** itself before launching it in the experimental mode below (otherwise the existing demo instance prevents a second instance):

```sh
open "$HOME/Applications/Codex Account Toggle.app" --args --live
```

This command is for your manual QA, not automated development tests. Save account A with **Save signed-in account**. Sign in to account B yourself in Codex and save B too. Test B→A→B, verify the account shown inside Codex after each restart, and check project/conversation availability. Cancel a switch confirmation and verify the current account stays selected. If quitting fails, the switch should stop without replacing credentials. Do not force a failure against real credentials; use demo scenarios for recovery testing.

The build is locally ad-hoc signed, not Developer ID signed or notarized. No installer, automatic updater, or Windows binary is provided yet. Double-clicking the app next time starts demo mode again; `--live` is not persisted. Send QA observations without authentication files, tokens, or personal account screenshots.
