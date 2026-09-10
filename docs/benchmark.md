# Account switcher benchmark / 벤치마크

Reviewed 2026-09-11. The user's approximate product name most closely matches [liuzhao1225/codex-account-switcher](https://github.com/liuzhao1225/codex-account-switcher). This is a working identification, not a confirmed link from the user.

Reference commit: `5f2a0352d33a26b479bbe614b9b80843f4c9cb16`. Reviewed README, published hero image, and native source. The reference app was **not installed or executed**. This is a feature/code review, not a performance benchmark or security audit.

## Findings and decisions

| Reference behavior | Value | Decision for this app |
| --- | --- | --- |
| Weekly allowance is the default; exact 300-minute row is optional | Avoids treating every account as having a five-hour limit | Weekly-first order added. Continue showing only actual supplied windows. |
| Menu-bar remaining percentage | Check capacity without opening the panel | Added with explicit `D` prefix for demo values; stale values have `~`. |
| Previously loaded usage remains during refresh/failure | Avoids blanking useful information | Added in the prepared current-account state layer; no false refresh timestamp. |
| Loading/loaded/stale/unavailable states | Explains confidence in data | Prepared typed states/errors; stale row copy and pending-connection UI added. |
| Refresh coalescing and five-minute background refresh | Avoids duplicate runtime launches | Added in-flight guard. Automatic real-account polling deferred until a safe adapter exists. |
| Inline, dismissible errors | Keeps the panel usable after a recoverable failure | Added dismiss control, except while busy or recovery is required. |
| Browser-based account onboarding in isolated profile homes | Removes manual file importing | High-priority next feature, but requires separate credential-lifecycle design and authorization before real testing. |
| Dedicated account management / confirmation page | Scales better than dense popovers | Keep visible account menus now; a management page is a future step. |
| Sparkle, signed/notarized DMG, checksums | Reduces install/update friction | Publication roadmap item. Upstream claims reviewed; releases/signatures not independently verified. |
| WPF Windows UI with shared Swift core/host | Native Windows tray experience | Useful architecture reference; porting our Darwin-dependent core is still required. |

## Implementation references

- [CodexClient.swift](https://github.com/liuzhao1225/codex-account-switcher/blob/5f2a0352d33a26b479bbe614b9b80843f4c9cb16/Sources/SwitcherCore/CodexClient.swift): starts `codex app-server --stdio`, assigns `CODEX_HOME`, initializes JSON-RPC, reads identity with `refreshToken: false`, requests rate limits. Its login method is separate but the runtime can still own refresh behavior.
- [AccountController.swift](https://github.com/liuzhao1225/codex-account-switcher/blob/5f2a0352d33a26b479bbe614b9b80843f4c9cb16/Sources/SwitcherCore/AccountController.swift): coalesces refreshes, retains usage on failures, refreshes saved profiles concurrently, supports periodic polling.
- [WeeklyUsageNormalizer.swift](https://github.com/liuzhao1225/codex-account-switcher/blob/5f2a0352d33a26b479bbe614b9b80843f4c9cb16/Sources/SwitcherCore/WeeklyUsageNormalizer.swift): identifies windows by duration, not primary/secondary position. Our implementation preserves service durations and does not guess missing windows.
- [MenuBarPopover.swift](https://github.com/liuzhao1225/codex-account-switcher/blob/5f2a0352d33a26b479bbe614b9b80843f4c9cb16/Sources/CodexAccountSwitcher/MenuBarPopover.swift): account, management, settings, confirmation pages; inline dismissible errors.

## License and originality

Reference license: MIT, Copyright (c) 2026 liuzhao1225. Direct source reuse would require preserving that copyright and permission notice. This change implements the selected behavior independently; no reference code, logo, icon, marketing image, or product name is copied into the app. Links identify the source of the comparison. The reference image was inspected locally, not redistributed in our screenshots.

## 인증정보 변경 위험

공식 Codex의 `account/read`는 `refreshToken: false`를 지원하지만, 이를 사용량 조회 전체가 인증정보를 변경하지 않는다는 보장으로 확대하면 안 된다. 아래 공식 소스에서 `account/rateLimits/read`는 `auth_manager.auth().await`를 호출하며, `auth()`는 조건에 따라 토큰을 갱신한다.

- [account_processor.rs](https://github.com/openai/codex/blob/e25bedc166b54acadb505b587a387091097b2393/codex-rs/app-server/src/request_processors/account_processor.rs)
- [auth/manager.rs](https://github.com/openai/codex/blob/e25bedc166b54acadb505b587a387091097b2393/codex-rs/login/src/auth/manager.rs)
- [Official account API documentation](https://learn.chatgpt.com/docs/app-server)

따라서 참고 앱의 별도 프로세스 실행 방식을 그대로 활성화하지 않는다. 현재 구현은 읽기 메서드만 표현할 수 있는 요청 모델, 가짜 전송 계층, 응답 ID 검증, 조회 전후 계정/리비전 확인, 오류 원문 제거, 이전 확인 값 유지까지다. 실제 토큰 파일을 읽거나 프로세스를 실행하는 전송 어댑터는 없다.
