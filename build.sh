#!/bin/bash
# Builds build/AgentSoundsBar.app (menu bar only, no Dock icon).
#
#   ./build.sh                              native arch, ad-hoc signed (local development)
#   UNIVERSAL=1 ./build.sh                  arm64 + x86_64
#   SIGN_IDENTITY="Developer ID Application: ..." ./build.sh
#                                           hardened runtime + secure timestamp, ready to notarize
#
# The version comes from the VERSION file; the build number is the git commit count.
set -euo pipefail
cd "$(dirname "$0")"

VERSION="$(tr -d '[:space:]' < VERSION)"
BUILD_NUMBER="$(git rev-list --count HEAD 2>/dev/null || echo 1)"
ARCHS=()
[ "${UNIVERSAL:-0}" = "1" ] && ARCHS=(--arch arm64 --arch x86_64)

swift build -c release ${ARCHS[@]+"${ARCHS[@]}"}
APP="build/AgentSoundsBar.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$(swift build -c release ${ARCHS[@]+"${ARCHS[@]}"} --show-bin-path)/AgentSoundsBar" "$APP/Contents/MacOS/"

# Everything the hooks need ships inside the app, so no repo checkout is required.
# Release builds bundle no audio (defaults are the macOS sounds); a local build can add its own
# by putting files in Resources/sounds.
mkdir -p "$APP/Contents/Resources"
cp scripts/play-sound "$APP/Contents/Resources/play-sound"
[ -d Resources/sounds ] && cp -R Resources/sounds "$APP/Contents/Resources/sounds"

# App icon: Liquid Glass Assets.car for macOS 26 plus AppIcon.icns for older systems.
# actool ships with Xcode, not the Command Line Tools; without it the app builds with no icon.
# Paths must be absolute: actool's helper daemon resolves relative ones against its own cwd.
if xcrun --find actool >/dev/null 2>&1; then
  xcrun actool "$PWD/Resources/AppIcon.icon" --compile "$PWD/$APP/Contents/Resources" \
    --app-icon AppIcon --platform macosx --minimum-deployment-target 14.0 \
    --output-partial-info-plist "$PWD/build/icon-partial.plist" >/dev/null
else
  echo "warning: actool not found (needs Xcode), building without an app icon" >&2
fi

cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>com.alexisaraujo.AgentSoundsBar</string>
  <key>CFBundleName</key><string>AgentSoundsBar</string>
  <key>CFBundleDisplayName</key><string>Agent Sounds Bar</string>
  <key>CFBundleExecutable</key><string>AgentSoundsBar</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleIconName</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$BUILD_NUMBER</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.developer-tools</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHumanReadableCopyright</key><string>Copyright © 2026 Enrique Alexis Araujo. MIT License.</string>
</dict>
</plist>
EOF

if [ -n "${SIGN_IDENTITY:-}" ]; then
  codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP"
else
  codesign --force --sign - "$APP" >/dev/null
fi
echo "built $APP $VERSION ($BUILD_NUMBER)"
