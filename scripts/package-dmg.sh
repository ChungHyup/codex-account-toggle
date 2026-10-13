#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
version="0.3.0-beta.1"
app="dist/Pinch Hitter.app"
codesign --verify --strict "$app"
architectures=$(lipo -archs "$app/Contents/MacOS/CodexAccountToggle")
if [[ "$architectures" != *arm64* || "$architectures" != *x86_64* ]]; then
  echo 'Build a universal app first: UNIVERSAL=1 bash scripts/build-app.sh' >&2
  exit 1
fi
stage=$(mktemp -d "${TMPDIR:-/tmp}/cat-dmg.XXXXXX")
trap 'rm -rf "$stage"' EXIT
ditto "$app" "$stage/Pinch Hitter.app"
ln -s /Applications "$stage/Applications"
cp LICENSE "$stage/LICENSE.txt"
cat > "$stage/INSTALL.txt" <<'TXT'
Pinch Hitter — 0.3.0 beta 1 (formerly Codex Account Toggle)

Drag Pinch Hitter.app into Applications, then open it.
Fresh installs start in demo mode. Live mode is remembered if you enabled it previously.
Upgrading from Codex Account Toggle: quit it from the menu bar first, then move it to the Trash.
Saved accounts and settings carry over.
Requires macOS 13+; Apple Silicon and Intel code are included.
Codex switching requires the Codex desktop app; the Claude tab works with Claude desktop and Claude Code.

This QA beta is ad-hoc signed and NOT notarized. macOS may block downloaded apps.
Do not disable system security globally. Build from source if needed.

DMG를 열고 앱을 Applications로 드래그하세요.
처음 설치하면 데모이며, 이전에 실사용 모드를 켰다면 해당 설정이 유지됩니다.
Codex Account Toggle을 쓰던 경우 메뉴 막대에서 먼저 종료한 뒤 휴지통으로 옮기세요. 저장된 계정과 설정은 그대로 이어집니다.
이번 QA 베타는 공증 전 버전입니다. 필요하면 소스에서 직접 빌드하세요.

Guide: https://github.com/ChungHyup/pinch-hitter
TXT
output="dist/Pinch-Hitter-${version}-universal.dmg"
hdiutil create -volname 'Pinch Hitter' -srcfolder "$stage" -format UDZO -ov "$output"
hdiutil verify "$output"
(cd dist && shasum -a 256 "Pinch-Hitter-${version}-universal.dmg" > SHA256SUMS.txt)
echo "Packaged: $output"
