#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="RollingCalendar"
BUNDLE="build/${APP_NAME}.app"
BUNDLE_ID="io.github.macos-menubar-rollingcalendar"

echo "==> Cleaning"
rm -rf build
mkdir -p "${BUNDLE}/Contents/MacOS" "${BUNDLE}/Contents/Resources"

echo "==> Compiling"
swiftc -O \
  -target "$(uname -m)-apple-macosx13.0" \
  -framework AppKit \
  Sources/main.swift \
  Sources/ICS.swift \
  Sources/TimelineView.swift \
  Sources/CalendarSource.swift \
  Sources/CalendarRowView.swift \
  Sources/DemoData.swift \
  Sources/GoogleAuth.swift \
  Sources/GoogleCalendarAPI.swift \
  -o "${BUNDLE}/Contents/MacOS/${APP_NAME}"

echo "==> Writing Info.plist"
cat > "${BUNDLE}/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key><string>Rolling Calendar</string>
    <key>CFBundleExecutable</key><string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key><string>${BUNDLE_ID}</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

echo "==> Ad-hoc signing"
codesign --force --deep --sign - "${BUNDLE}" 2>/dev/null || echo "   (codesign skipped)"

echo ""
echo "Built: ${PWD}/${BUNDLE}"
echo "Run:   open '${PWD}/${BUNDLE}'"
