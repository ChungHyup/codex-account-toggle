# 참고 프로젝트 검토

검토일: 2026-09-10. 대상: https://github.com/ScWen7/CodexSwitch 의 커밋 `65469fc42160ae89a16c8829dd9babe2950d569e`.

- MIT License, Copyright (c) 2026 scwen. 코드 재사용 시 저작권/허가문 유지 필요. 이번 앱은 Swift 신규 구현이며 원본 코드를 포함하지 않음.
- `internal/switcher/switcher.go`: 사전 검증, 프로세스 종료 대기, 현재 프로필 동기화, 백업, auth.json 교체, 파일 검증, 앱 실행 구조. `stageNoRestore`는 앱 열기 실패에서 복구를 생략함. 이번 구현은 실패 시 프로세스가 종료되어 있을 때 복구하며, 그렇지 않으면 복구 파일을 남김.
- `internal/auth/auth.go`: ChatGPT access/refresh token 검증, JWT에서 표시용 메타데이터 추출. JWT 디코딩은 서버 인증 검증이 아님.
- `internal/fsutil/fsutil.go`: 전용 권한 파일, 임시 파일, fsync, rename. 신규 구현에도 해당 안전한 파일 교체 패턴 적용.
- 원본 내부 패키지의 HTTP 및 프로세스 실행 호출을 검색하고 전환/인증/파일 저장 경로를 읽음. 전체 저장소 보안 감사는 아님. 원본 사용량 수집 기능은 포함하지 않음.
- 공식 문서 https://learn.chatgpt.com/docs/auth : auth.json 또는 OS 자격 증명 저장소 사용, cli_auth_credentials_store 설정 및 토큰 취급 안내 확인. 데스크톱 버전별 파일 교체 호환성은 문서로 확정할 수 없음.

## 실제 전환 테스트 (미실행)

모든 Codex 작업 완료 후 사용자가 테스트 시점을 선택해야 함. 두 계정 등록, A→B→A 후 앱 표시 계정 확인, 대화/프로젝트/스킬/설정 유지 확인, 종료 거부 시 무변경, 재실행 실패 시 복구를 검증할 것. 현재 Codex 작업을 종료하는 테스트는 개발 중 실행하지 않음.
