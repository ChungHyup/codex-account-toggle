# Current account read preparation

`CurrentAccountReader` is an integration boundary, **not a live connection**. It does not launch Codex, read tokens, change files, or make HTTP requests. The UI's real-account data source is still disconnected.

## Prepared sequence

1. `account/read` with `refreshToken: false`.
2. `account/rateLimits/read`.
3. Repeat `account/read` and reject results if account metadata or the transport's identity revision changed.

Only those two request methods can be constructed. Response IDs and size are checked. A future transport must enforce the ten-second deadline and size limit while receiving data, and advance `identityRevision` on connection, account, or workspace changes. Raw errors never reach the UI. A returned reading uses a session-scoped key; email is never used to assign it to a saved profile. A null email is supported.

`CurrentUsageState` preserves a previous reading with its original timestamp during transient failures, prevents simultaneous refreshes, and clears cached identity data on sign-out/unsupported identity/change. It is in-memory only. Connecting this state to the panel requires a validated transport; it is not silently backed by a credential file.

## Production adapter (implemented 2026-09-14, owner-authorized)

`AppServerTransport` starts `codex app-server --stdio` from the Codex app bundle (or a CLI install), sends `initialize` and `initialized`, forwards only the two read methods, and stops the server after the read or five idle seconds. It enforces the ten-second deadline and the 1 MiB reply limit, refuses a server whose `codexHome` differs from this app's credential home, rotates `identityRevision` on launch, shutdown, `account/updated`, and `account/login/completed`, and discards stderr. The accepted side effect is that Codex may refresh the signed-in account's tokens during the read; see AGENTS.md. Saved inactive accounts are never queried. Tests use a fake shell executable with synthetic replies.

## Original adapter requirements

- Prefer a supported existing-host read-only interface whose credential side effects are documented and controlled. The assistant's app tool is not automatically callable by a third-party menu-bar app.
- A new `app-server` process is not currently acceptable under the user's no-credential-change rule: upstream `auth()` can refresh tokens even on a usage-read path.
- Do not copy auth.json, invoke login/logout, consume reset credits, or rotate identities to obtain quota data.
- Enforce cancellation/deadlines, account-change notifications, bounded reads, response ID correlation, and private metadata handling at the transport boundary.
- If strict no-write behavior cannot be established, leave live mode disconnected and describe the blocker. Do not claim that an allowlisted request alone makes the runtime side-effect-free.

All tests use synthetic JSON responses. No real account query or switch was performed as part of this preparation.

## Local session-log path (implemented 2026-09-14)

Live mode now displays the last `token_count.rate_limits` reading that Codex wrote to `CODEX_HOME/sessions`, following the reference project's approach. See `SessionUsage.swift` and [usage.md](usage.md) for the attribution rules. This does not connect the reader above: it is file reading only, with no process launch, request, or credential access, so the token-refresh concern does not apply.
