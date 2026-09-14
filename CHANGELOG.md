# Changelog

## Unreleased

- Compacted the menu-bar panel to a 264-point-wide, content-sized list (about 174 points for three accounts): one line per account, quota on the signed-in row, rename via right-click, demo scenario and display options in the gear menu.
- Live mode reads the signed-in account's current quota through a short-lived `codex app-server` process (owner-authorized); saved inactive accounts are never queried.
- Live mode shows the last quota reading Codex recorded in this Mac's session logs for other saved accounts, attributed through the app's own save/switch history.
- Clarified switch confirmation: running Codex/CLI requires an explicit restart action; Cancel is the default.

- Renamed the app and build artifacts to Codex Account Toggle; preserved the existing profile-storage path.

- Compacted the menu-bar panel from 380 × 680 to 320 × 540 points with tighter cards, smaller avatars, and inline reset dates.

- Removed the five-hour sample window from demo accounts and refreshed screenshots; demo quota is weekly-only.
- Prepared a current-account read client with a fake transport, response/identity validation, and stale-cache handling; live transport remains disconnected.
- Added weekly-first ordering, demo-labeled menu-bar quota, and dismissible notices after a source-based competitor review.

- Adopted the MIT License (copyright © 2026 Chunghyup OH).

- macOS menu-bar app with safe demo mode and three synthetic accounts.
- Account naming, switching coordinator, backup and recovery with fake lifecycle tests.
- Korean and English interface, dialogs, errors, and reset date formatting.
- Usage and plan presentation with explicit sample/unknown states; absent quota windows are hidden.
- Korea-time reset dates and countdowns, including expired and unknown states.
- Publication documentation, contributor templates, and macOS CI configuration.

Not yet shipped: Windows support, production account-switch verification, usage for inactive accounts beyond local records, Developer ID signing, notarization, and an automatic updater.
