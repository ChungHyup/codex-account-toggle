# 0.3.0 beta release review

Reviewed 2026-10-13. Scope: everything since `v0.2.0-beta.1`: the rename to Pinch Hitter and the new bundle identifier, Claude desktop and terminal Claude Code switching, Claude usage, Codex credit mode, live-read fixes, packaging and docs. The owner QA'd real Codex switching, real Claude desktop switching, and the renamed app on their Mac; this review did not repeat real switching or inspect production credentials.

## What changed for an upgrading user

- The app is now `Pinch Hitter.app` with bundle identifier `com.chunghyup.pinch-hitter`. On first launch it copies the old identifier's preferences once (live mode, panel tab, language, menu bar position), never overwriting or deleting. If `Codex Account Toggle` is still running, the new app explains and quits; it never terminates the old one.
- Storage paths are unchanged (`~/Library/Application Support/CodexSwitch`, `~/.codex-account-toggle`), so saved Codex accounts, saved Claude desktop accounts, and terminal account folders carry over. A shim installed by the earlier version is rewritten in place.
- The repository moved to `ChungHyup/pinch-hitter`; GitHub redirects the old URL.

## Safety properties checked

- Claude desktop switching never force-quits Claude, refuses a data folder it did not create, and repoints its link with rename(2) after the app and its helpers have quit. Tests run on `DesktopDemoWorkspace` temporary folders with a fake lifecycle.
- Terminal switching rewrites a one-line file; the app never edits shell startup files.
- Claude usage reads local files only (`plan-usage-history.json`, the tail of recent Claude Code transcripts). No credentials, cookies, or network calls.
- Codex live reads use the owner-authorized short-lived `codex app-server` for the signed-in account only.
- Offscreen renders and tests do not read or write the live-mode preference; the preference migration test exercises value selection only.

## Release decision

Suitable for an explicitly labeled **QA prerelease**. Not a production or security certification.

Remaining limits: ad-hoc signature without Developer ID or notarization; Intel hardware QA pending; no auto-update; Codex credentials are file-based plaintext copies with private permissions; Claude desktop switching depends on the app's current data layout and stops when it changes; the 5-hour Claude reset is an estimate and the weekly reset comes from the user's setting; a Claude Code limit refusal from the desktop Code tab is attributed to the desktop account active since the last switch. An upgrade test from the mounted DMG over a `0.2.0-beta.1` install has not been run.

## Verification recorded

100 synthetic tests passed. Universal arm64/x86_64 build succeeded. `hdiutil verify` passed and the checksum in `SHA256SUMS.txt` matches. The read-only mounted DMG contains `Pinch Hitter.app`, the `/Applications` link, `INSTALL.txt`, and `LICENSE.txt`; the app passed strict codesign verification, has both architectures, bundle identifier `com.chunghyup.pinch-hitter`, version 0.3.0 (3), and the expected icon bytes. The app was not launched from the mounted DMG. README screenshots were re-rendered from synthetic fixtures.
