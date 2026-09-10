# Development constraints

- The user explicitly prohibits real logout, account switching, changes to real credentials, or terminating Codex during development/testing.
- All automated tests must use fresh temporary directories, synthetic credentials, and an injected fake application lifecycle.
- Do not launch the app with `--live` during development or testing. Normal launches must remain demo mode by default.
- Never read, print, copy, or modify real authentication tokens for debugging. Never use production credentials as fixtures.
- Only a new, explicit user request can authorize testing a real account switch. The general request to continue development is not that authorization.
- Do not control or terminate the user's running Codex or CLI processes to make tests pass.
- Keep coherent, tested changes in Git commits as development proceeds. Never claim a commit exists without checking Git. Do not rewrite history or push to a remote without user authorization.
- Before staging, exclude credentials, real account data, build output, signing keys, and local environment files. Use synthetic fixtures only.
