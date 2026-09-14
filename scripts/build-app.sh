#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
build_args=(-c release --disable-sandbox)
if [[ "${UNIVERSAL:-0}" == 1 ]]; then build_args+=(--arch arm64 --arch x86_64); fi
swift build "${build_args[@]}"
bin_dir=$(swift build "${build_args[@]}" --show-bin-path)
app="dist/Codex Account Toggle.app"
mkdir -p "$app/Contents/MacOS"
cp "$bin_dir/CodexAccountToggle" "$app/Contents/MacOS/CodexAccountToggle"
mkdir -p "$app/Contents/Resources"
cp LICENSE "$app/Contents/Resources/LICENSE"
cp assets/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"
cp -R "$bin_dir/CodexAccountToggle_SwitchCore.bundle" "$app/Contents/Resources/"
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>CodexAccountToggle</string>
<key>CFBundleIdentifier</key><string>com.chunghyup.codex-account-toggle</string>
<key>CFBundleName</key><string>Codex Account Toggle</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.2.0</string>
<key>CFBundleVersion</key><string>2</string>
<key>CFBundleDevelopmentRegion</key><string>en</string>
<key>CFBundleLocalizations</key><array><string>en</string><string>ko</string></array>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --sign - "$app"
echo "Built: $app"
