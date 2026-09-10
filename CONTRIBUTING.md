# Contributing

[한국어](#한국어)

Use macOS 13+ with Xcode Command Line Tools and Swift 5.9+. Start with `swift test --disable-sandbox` and `bash scripts/build-app.sh`. The default app is a demo; never run `--live` for development or automated tests. Tests must use temporary directories, synthetic credentials, and the injected fake lifecycle. Do not quit or log out the maintainer's running Codex session.

Keep commits focused. For UI work, render both `--language=en` and `--language=ko` in light and dark modes. Do not include real account screenshots or log files in issues or PRs. Run `python3 scripts/check-public.py` before committing. It is a heuristic check, not a full secret scanner or security audit.

Translations live in `Sources/SwitchCore/Resources/en.json` and `ko.json`. Korean source phrases are stable lookup keys. Add the same key to both files and preserve every `%@` placeholder in order. Use `L10n.text` for static strings and `L10n.format` for arguments; do not translate account IDs, user-defined names, or protocol fields. Date formatting lives in `ResetSchedule`; keep Korea time explicit. The language menu applies on the next Switch launch.

This repository does not yet have a selected license. Resolve that before accepting external contributions or publishing a release.

## 한국어

macOS 13 이상, Swift 5.9 이상에서 빌드합니다. 테스트와 개발은 데모·가짜 인증정보·임시 폴더만 사용하고 `--live`를 실행하지 않습니다. 실제 로그아웃, 로그인 교체, Codex 종료는 금지합니다.

변경 단위로 커밋하고, UI 변경은 한국어·영어와 라이트·다크 모드를 확인합니다. 번역 JSON의 키와 `%@` 인자 수를 양쪽 언어에서 맞추세요. 계정 식별자나 사용자가 지정한 이름은 번역하지 않습니다. 공개 자료에는 실제 계정 화면과 로그를 포함하지 마세요.
