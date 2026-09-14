#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
version="0.2.0-beta.1"
app="dist/Codex Account Toggle.app"
codesign --verify --strict "$app"
architectures=$(lipo -archs "$app/Contents/MacOS/CodexAccountToggle")
if [[ "$architectures" != *arm64* || "$architectures" != *x86_64* ]]; then
  echo 'Build a universal app first: UNIVERSAL=1 bash scripts/build-app.sh' >&2
  exit 1
fi
stage=$(mktemp -d "${TMPDIR:-/tmp}/cat-dmg.XXXXXX")
trap 'rm -rf "$stage"' EXIT
ditto "$app" "$stage/Codex Account Toggle.app"
ln -s /Applications "$stage/Applications"
cp LICENSE "$stage/LICENSE.txt"
cat > "$stage/INSTALL.txt" <<'TXT'
Codex Account Toggle — 0.2.0 beta 1

Drag Codex Account Toggle.app into Applications, then open it.
Fresh installs start in demo mode. Live mode is remembered if you enabled it previously.
Requires macOS 13+; Apple Silicon and Intel code are included.
Real account switching requires the Codex desktop app.

This QA beta is ad-hoc signed and NOT notarized. macOS may block downloaded apps.
Do not disable system security globally. Build from source if needed.

DMG를 열고 앱을 Applications로 드래그하세요.
처음 설치하면 데모이며, 이전에 실사용 모드를 켰다면 해당 설정이 유지됩니다.
이번 QA 베타는 공증 전 버전입니다. 필요하면 소스에서 직접 빌드하세요.

Guide: https://github.com/ChungHyup/codex-account-toggle
TXT
output="dist/Codex-Account-Toggle-${version}-universal.dmg"
hdiutil create -volname 'Codex Account Toggle' -srcfolder "$stage" -format UDZO -ov "$output"
hdiutil verify "$output"
(cd dist && shasum -a 256 "Codex-Account-Toggle-${version}-universal.dmg" > SHA256SUMS.txt)
echo "Packaged: $output"
