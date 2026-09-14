#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release --disable-sandbox
app="dist/Codex Account Toggle.app"
mkdir -p "$app/Contents/MacOS"
cp .build/release/CodexAccountToggle "$app/Contents/MacOS/CodexAccountToggle"
mkdir -p "$app/Contents/Resources"
cp LICENSE "$app/Contents/Resources/LICENSE"
cp assets/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"
cp -R .build/release/CodexAccountToggle_SwitchCore.bundle "$app/Contents/Resources/"
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>CodexAccountToggle</string>
<key>CFBundleIdentifier</key><string>com.chunghyup.codex-account-toggle</string>
<key>CFBundleName</key><string>Codex Account Toggle</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
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
