# Security and privacy

This is an experimental local utility, not an official OpenAI product. Real account switching and live usage integration have not been validated end to end. Default launches use synthetic demo accounts.

In experimental live mode, credential snapshots are **plaintext**, restricted to the current user with directory mode 0700 and file mode 0600. This is not encryption or Keychain storage. The utility has no telemetry or network client. Codex itself may contact its service when the user runs it.

Do not post auth.json, access/refresh tokens, session logs, account identifiers, or private screenshots in public issues. Use GitHub's private vulnerability reporting feature when it is enabled on the published repository. If it is unavailable, ask the maintainer for a private reporting channel without disclosing exploit details or secrets publicly. No private email address is collected or published here.

Before publication, enable private vulnerability reporting and secret scanning where available. Signing and notarization credentials must stay out of the repository. There are no security support guarantees or validated production releases yet.

## 한국어

실계정 인증 사본은 암호화가 아닌 파일 권한으로 보호합니다. 실시간 사용량 연동과 실제 전환은 아직 통합 검증 전입니다. 인증정보·계정 식별자·세션 로그는 공개 이슈에 올리지 마세요. 저장소 공개 시 비공개 취약점 제보 기능을 활성화해야 합니다.
