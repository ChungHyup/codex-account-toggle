# Claude desktop accounts / Claude 데스크톱 계정 전환

Added 2026-10-13. Unofficial: Claude desktop has no account switcher, and this relies on how the app stores its data today.

## How it works

Claude desktop (`com.anthropic.claudefordesktop`) keeps its sign-in cookies, the encrypted token cache in `config.json`, and the last account id (`lastKnownAccountUuid`) in `~/Library/Application Support/Claude`. Preferences, caches, and the Keychain item "Claude Safe Storage" hold no per-account state; the encryption key is per app, so every account folder decrypts with it. The desktop Code tab authenticates through the desktop app (host auth), so it follows the desktop account.

- Each saved account has its own folder under `~/Library/Application Support/CodexSwitch/claude-desktop/profiles/<id>`. `<id>` is generated and never changes; names live in `profiles.json`, so renaming is display-only.
- The data folder path becomes a symlink to the active account's folder. A switch quits Claude, creates a new link beside the old one and `rename(2)`s it over, then reopens Claude. The path is never missing, and nothing is copied or deleted.
- The app's own folder is adopted on the first switch with one same-volume rename. A cross-volume move fails rather than copying many gigabytes.
- Adding an account links an empty folder; Claude opens on its sign-in screen and the previous account's folder stays intact (no sign-out).
- A real folder, foreign link, or file at the path is never replaced. If the path goes missing after management, the last account is relinked instead of letting Claude start signed out.
- The switch waits for Claude, its helpers, and Code binaries running from the data folder to exit. It never force-quits; if Claude does not quit, nothing changes. The Chrome bridge helper (`Contents/Helpers/chrome-native-host`) is started by Chrome and does not use the data folder, so it does not block.
- Deleting a saved account moves its folder to the Trash.

## Limits

- One account at a time; a switch restarts Claude and stops running chats and Code or Cowork work.
- Chat-tab conversations live on Anthropic's servers per account. Code-tab session lists are per account folder; carrying them across accounts is planned (see the references below), and transcripts in `~/.claude/projects` are already shared on disk.
- Cowork's VM bundle (about 10 GB here) is stored per account folder, so a newly added account downloads its own copy the first time it uses Cowork.
- An app update that changes the data layout can break switching; the design stops instead of guessing.

## References

Design adapted from two MIT-licensed projects; no code is vendored.

- [ajipurn/agent-profiles](https://github.com/ajipurn/agent-profiles) `3cf3911`: symlinked data folder, atomic link replacement, generated folder ids, CLI profiles via `CLAUDE_CONFIG_DIR`, shared Code-tab session history.
- [erorplex/claude-desktop-profiles-macos](https://github.com/erorplex/claude-desktop-profiles-macos) `ce248fe`: whole-folder switching, graceful quit with no changes on refusal, Code-tab session sync, documented caveats.

Reviewed but not adopted: cloning the app with `--user-data-dir` for side-by-side accounts (odahcam, serhii-chernenko; needs re-signing and an update watchdog), swapping only cookie files (SnlperStripes, NeezerGu; depends on finer internals), and decrypting the token cache to call usage APIs (SnlperStripes).

## Owner QA

Development and tests use synthetic folders and a fake app only. To try it for real: finish running Claude work, open the panel's Claude tab, and use **Add account → Sign in to another Claude account…**. Name the current account when asked, sign in to the other account in the reopened Claude, then switch back and forth from the panel. Confirm the account shown inside Claude after each switch.
