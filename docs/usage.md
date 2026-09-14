# 사용량 표시

2026-09-10 공식 문서 확인: https://learn.chatgpt.com/docs/app-server

- account/read 또는 account/updated의 planType으로 요금제 표시 가능.
- account/rateLimits/read 및 account/rateLimits/updated는 usedPercent, windowDurationMins, resetsAt를 제공.
- rateLimitsByLimitId가 있으면 codex 버킷을 사용. 없을 때만 legacy rateLimits 사용. 다른 버킷을 Codex 한도로 오인하지 않음.
- 남은 한도는 100 - usedPercent, 0~100 범위. unknown/null을 0 또는 100으로 바꾸지 않음.
- 토큰 활동 통계 account/usage/read와 한도 비율은 다른 지표이며, 잔여 토큰 수로 표기하지 않음.

현재 구현은 파서·샘플 제공자·표시 UI까지. 앱 서버 실시간 연결은 미구현. Codex 앱 도구에서 읽을 수 있는 현재 계정 사용량을 별도 메뉴바 앱이 자동으로 호출할 수 있다고 가정하지 않음. 여러 계정의 실시간 조회도 검증하지 않음. 세션 기록 기반 수집은 아래 규칙으로만 계정에 귀속한다.

추가 준비: [현재 계정 조회 경계](read-only-connection.md)와 [벤치마크](benchmark.md). 공식 앱 서버 조회의 자동 토큰 갱신 경로를 확인했으므로 실제 프로세스 어댑터는 연결하지 않았다. 읽기 요청 모델·응답 검증·이전 값 유지·계정 변경 시 폐기 로직은 가짜 응답으로 검증한다.

실계정 테스트 금지 지침을 유지한다. 조회 기능 연결 전 토큰 갱신·저장 부작용을 검토해야 한다. 앱 종료·로그아웃·계정 전환으로 사용량을 얻는 방식은 사용하지 않는다.

## 로컬 세션 기록 기반 수집 (2026-09-14)

참고 프로젝트 [ScWen7/CodexSwitch](https://github.com/ScWen7/CodexSwitch) `65469fc`의 `internal/quota/sessionlog.go`와 같은 방식이다. `SessionUsage.swift`가 `CODEX_HOME/sessions/**/*.jsonl`에서 `event_msg` 중 `token_count`의 `rate_limits`만 읽는다. 최신 파일 60개까지, 각 파일은 끝 256KB만 읽고 없으면 전체(32MB 이하)를 한 번 더 읽는다. `limit_id`가 `codex`가 아니면 무시하고, `rate_limits_by_limit_id`는 아직 관찰되지 않았다. Codex 실행, 요청 전송, 로그인 파일 접근은 없다.

- 세션 기록에는 계정 정보가 없다. 앱이 로그인 계정을 확인한 시점(`identity-points.json`: `saved`·`observed`·`switched`)으로만 귀속한다.
- 앱이 수행한 전환(`switched`)은 정확한 경계다. 패널이 다른 계정을 발견한 경우(`observed`, `saved`)는 바뀐 시점을 모르므로 그 사이 값은 버린다.
- 처음 확인보다 오래된 값은 참고 프로젝트처럼 처음 저장·확인한 계정의 것으로 간주한다. 이 가정은 README에 명시한다.
- 프로필별 최신 값은 `usage.json`(0600)에 보존해 Codex가 로그를 정리해도 비활성 계정의 마지막 값을 유지한다.
- 이 값은 Codex를 사용해야 갱신되므로 '새로고침 필요' 대신 기록 시각을 표시한다. 메뉴바에도 `~` 표시를 붙이지 않는다.
- 저장 폴더가 없는 상태에서는 아무것도 쓰지 않으며, 패널을 열 때와 5분마다 다시 읽는다.

## 초기화 날짜 표시

선택한 계정의 각 한도 아래에 날짜(오늘/내일 포함), 정확한 오전·오후 시각, 남은 시간을 함께 표시한다. 한국 시간 Asia/Seoul 기준이며 시스템 시간대와 무관하다. 연도가 다르면 연도를 표시하고, 도움말에는 연도·요일·초·KST까지 제공한다. 패널을 열어 둔 동안 남은 시간은 30초마다 다시 계산한다. 이 갱신은 네트워크 요청이 아닌 로컬 시간 계산이다.

시각이 지나면 비율을 자동으로 100%로 바꾸지 않고 '시각 지남 · 새로고침 필요'를 표시한다. 누락되거나 유효하지 않은 날짜는 '초기화 날짜 미확인'으로 표시한다. 실시간 조회는 여전히 미연결이며 데모의 초기화 날짜도 샘플이다.
