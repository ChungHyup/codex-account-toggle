#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release --disable-sandbox
app="dist/Codex Switch.app"
mkdir -p "$app/Contents/MacOS"
cp .build/release/CodexSwitch "$app/Contents/MacOS/CodexSwitch"
mkdir -p "$app/Contents/Resources"
cp LICENSE "$app/Contents/Resources/LICENSE"
if [[ -d "$app/CodexSwitch_SwitchCore.bundle" ]]; then
  mv "$app/CodexSwitch_SwitchCore.bundle" "$app/Contents/Resources/"
fi
cp -R .build/release/CodexSwitch_SwitchCore.bundle "$app/Contents/Resources/"
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>CodexSwitch</string>
<key>CFBundleIdentifier</key><string>local.codexswitch.menubar</string>
<key>CFBundleName</key><string>Codex Switch</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.1.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>CFBundleDevelopmentRegion</key><string>en</string>
<key>CFBundleLocalizations</key><array><string>en</string><string>ko</string></array>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --sign - "$app"
echo "Built: $app"
