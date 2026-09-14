# Usage readings / 사용량 표시

Updated 2026-09-14 for 0.2.0 beta.

## Current account

In real-account mode, `AppServerTransport` starts a short-lived `codex app-server` for the active `CODEX_HOME`. It sends initialize, `account/read` with `refreshToken: false`, `account/rateLimits/read`, and a second identity read. The model checks that the active local identity still matches before displaying the result. This path may let Codex refresh the active account's credentials; the owner accepted that behavior. No inactive account is activated to collect quota.

Remaining percentage means `100 - usedPercent`, clamped to 0–100. Missing values remain unknown. The Codex bucket is preferred in `rateLimitsByLimitId`; another bucket is never substituted. The service's actual window duration determines the label. These are usage allowances, not token balances.

## Local history

Inactive accounts can show a last known reading extracted from local `sessions/**/*.jsonl` token-count events. A recent-file scan uses tails first, with a bounded-size full-file fallback. Unrelated rollout content is discarded, not stored as conversation data.

Attribution uses recorded identity observations and this app's switch boundaries. **Readings before the first identity confirmation are not attributed.** Intervals where an external account change was detected but its time is unknown are discarded. Old cache entries that fail the current attribution rules are excluded. Unobserved external sign-in changes remain a limitation: local history is a best-effort last-known reading, not a live guarantee.

Snapshots are stored as private `usage.json` files in the application's existing profile directory. A recorded value is labeled as history and keeps its observation time. It does not imply the inactive account was contacted.

## Refresh and dates

The app refreshes on panel opening and approximately every four minutes. Live attempts are throttled to at least 60 seconds unless explicitly forced, and skipped during switching, recovery, or account onboarding. Reset labels update locally every 30 seconds. Dates use Asia/Seoul (KST), including in English. Expired values are not automatically replaced by 100%.

실사용 모드의 현재 계정 조회는 연결되어 있습니다. 비활성 계정은 로컬 기록이 있을 때만 표시하며, 최초 계정 확인 이전 값은 추정하지 않습니다. 잔여 %는 토큰 수가 아니라 사용 한도이고, 실제로 제공된 구간만 표시합니다. 실계정 QA는 사용자가 별도로 수행하며 자동 테스트는 가짜 응답과 임시 폴더만 사용합니다.
