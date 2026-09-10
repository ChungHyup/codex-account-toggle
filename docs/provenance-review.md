# Reference-content review

Reviewed 2026-09-11 against local commit `57a95c0` (40 tracked files).

## What is included

| Location | Content |
| --- | --- |
| `README.md` | Reference-project link and a statement about independent implementation. |
| `docs/review.md` | Our review of ScWen7/CodexSwitch, including its MIT notice, source paths, behavior, and implementation differences. |
| `docs/benchmark.md` | Our comparison with liuzhao1225/codex-account-switcher, source links, MIT attribution, and adopted/deferred behavior. |
| `README.ko.md`, `docs/usage.md` | Links to those reviews. |
| `docs/read-only-connection.md` | Our integration constraints, informed by official Codex behavior. |

These are reference notes written for this project. They are tracked and would be included in a public source repository. The build script does not bundle these documents into the app. Preserve this record of design influences; it is not a vendored implementation.

## Comparison performed

Compared the current tracked files against the previously reviewed local source checkouts:

- ScWen7/CodexSwitch: `65469fc42160ae89a16c8829dd9babe2950d569e`.
- liuzhao1225/codex-account-switcher: `5f2a0352d33a26b479bbe614b9b80843f4c9cb16`.

No byte-identical files were found (SHA-256 comparison). No identical runs of eight nonempty, whitespace-trimmed source lines were found across Swift, Go, Python, and shell sources. This is a limited similarity check, not proof that no shorter or transformed passage could match. The design and implementation reviews explicitly acknowledge behavior learned from the references.

`Package.swift` has no external package dependencies. No submodules, vendored reference trees, reference artwork, or third-party executables appear in the tracked-file inventory. Historical path inspection found only this project's source, tests, documentation, scripts, and GitHub templates; this was not a full content comparison of every historical blob.

The three tracked PNGs are renders of our SwiftUI panel with synthetic accounts. The latest app bundle contains its executable, bundle metadata/signature, our MIT license, and Korean/English resources. It contains no reference screenshots or benchmark documents. Reference checkouts were inspected outside this repository and were not installed or run.

The existing tracked-source heuristic check and localization parity check passed. That check is not a full historical secret scan. No real credentials were read for this review.

## Naming decision

The former `Codex Switch` name overlaps with [ScWen7/CodexSwitch](https://github.com/ScWen7/CodexSwitch) and closely with [Codex Switcher](https://www.codexswitch.com/). The owner selected **Codex Account Toggle**, with repository slug `codex-account-toggle` and description “Switch Codex accounts from your menu bar.”

The app, executable, Swift package/target, resource bundle, bundle identifier, build script, CI, UI translations, and screenshots use the selected name. Reference-project names and source links retain their original spelling.

The existing `Library/Application Support/CodexSwitch` profile path is deliberately preserved. This rename does not inspect or migrate credentials. The new bundle identifier is `com.chunghyup.codex-account-toggle`; preferences under the old identifier are not migrated. An already running old-name app prevents a second normal instance from starting; the old process is never terminated. The local checkout directory remains unchanged. Repository creation and remote publication are pending.
