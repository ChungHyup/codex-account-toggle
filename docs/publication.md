# Publication status

The repository is public (`ChungHyup/codex-account-toggle`, MIT) and `v0.2.0-beta.1` is a public prerelease with a universal DMG and checksum. This page tracks what remains before a wider announcement and a non-beta release.

Done:

- English and Korean product READMEs, contribution guide, security notes, changelog, issue/PR templates.
- Korean/English resources with parity tests; screenshots rendered from synthetic fixtures only.
- Synthetic-account test suite, fake-executable tests for the usage transport and temporary-home login, read-only-permission macOS CI.
- Original icon and banner generated from vector geometry; no reference artwork bundled.
- Owner-validated real switching and live usage read with the Codex desktop app (see AGENTS.md authorizations).

Before announcing widely:

1. Apple Developer Program: sign with Developer ID and notarize the DMG so first launch does not require the Gatekeeper approval steps in the README. This is the single biggest install-friction item.
2. Enable private vulnerability reporting and secret scanning in the repository settings; add branch protection for `main` requiring the CI check.
3. Add repository topics and a social preview image so the project is discoverable and shares well.
4. Record a short demo (switch, quota, add account) with fictional or masked accounts; never show real emails or tokens.
5. Decide the support policy for issues (macOS versions, Codex desktop versions) and write a short FAQ: Gatekeeper, "do not log out in the ChatGPT app", per-account remote/cloud thread visibility, KST reset times.

Before a non-beta release:

- Intel hardware QA, a run from the mounted DMG, and an upgrade test over the previous beta.
- Decide whether reset times should follow the Mac's timezone instead of KST.
- Optional: Homebrew cask and an auto-update channel once notarization exists.
