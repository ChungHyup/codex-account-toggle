# Current-account usage connection

Implemented in 0.2.0 beta. `CurrentAccountReader` accepts only identity and rate-limit reads through an injected transport. It checks response IDs, size, account metadata, and transport identity revision before returning a snapshot. Errors are sanitized; missing email is supported.

`AppServerTransport` runs a short-lived Codex app-server with an explicit `CODEX_HOME`, handshakes, discards stderr, limits line size and request duration, observes identity notifications, and closes its own server after the read. It does not send login, logout, credits, or approval methods. The UI does not switch credentials to query inactive accounts.

**Read-only methods are not a promise of zero credential writes.** Codex may refresh the signed-in account's credentials internally. The owner accepted that runtime behavior on 2026-09-14. The earlier preparation-only constraint is superseded for the product, not for automated development tests.

Tests inject a fake executable and synthetic replies. Offscreen previews force demo mode without consulting or changing the live-mode preference. This review did not execute real sign-in, usage queries, switching, or Codex termination.

Local session history has separate attribution limitations; see [usage](usage.md). UI state, process timeouts, and identity checks are useful defenses, not a complete audit of Codex internals or every concurrent external writer.
