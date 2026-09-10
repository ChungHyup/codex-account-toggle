# Publication readiness

Prepared locally:

- English and Korean README, contribution guide, security notes, changelog.
- Korean/English resources and parity tests; demo-only screenshots.
- Pull request and issue templates; read-only-permission macOS CI.
- Synthetic-account test suite and ad-hoc signed local app.
- MIT license selected by the project owner; full text included in `LICENSE`.
- Ignore rules and source-only heuristic checks for common secret patterns.

Before making the repository public:

1. Retain `LICENSE` and the copyright notice in source distributions and packaged releases.
2. Choose/create the GitHub repository and confirm visibility. No remote has been created or pushed by this preparation work.
3. Enable private vulnerability reports and secret scanning where available; configure branch protection after CI exists remotely.
4. Run `python3 scripts/check-public.py --require-license` and the tests. Review staged changes and screenshots manually.
5. Be explicit that this is a demo-first experimental project. A public source repository is not a validated production binary release.

Before releasing a production binary, validate the real integration at an explicitly user-authorized time, decide the supported account-storage modes, sign with Developer ID, notarize, and provide build/version provenance. These steps are not automatically authorized by a request to prepare the source for publication.
