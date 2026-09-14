# Development and owner QA

Automated work uses synthetic credentials, fresh temporary directories, and fake executables/lifecycle. Never start the app normally during automated development: live mode may be remembered. Offscreen renders explicitly force demo mode without reading or changing the mode preference.

```sh
swift test --disable-sandbox
bash scripts/build-app.sh
'dist/Codex Account Toggle.app/Contents/MacOS/CodexAccountToggle' --render-preview --language=en
'dist/Codex Account Toggle.app/Contents/MacOS/CodexAccountToggle' --render-preview --product-preview --language=en
```

For owner-operated real QA only: finish Codex work and CLI sessions, save account A, add B through temporary-home browser login, switch A→B→A, confirm the account inside Codex, and verify access to existing projects and conversations. Test Cancel before confirming any restart. Use synthetic scenarios for refusal and recovery; do not provoke credential failures on real accounts.

On a Mac already using the old utility name, close that utility yourself before opening this app. The profile storage path stays unchanged; no credential migration is needed. A fresh preference domain starts in demo; a previous live preference stays live. Report OS/architecture, app version, and reproduction steps without tokens, auth files, or account screenshots.
