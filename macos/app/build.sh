#!/bin/bash
# Builds build/Cordelia.app with the Xcode command line tools alone
# (xcode-select --install). No Xcode project, no dependencies.
set -euo pipefail
cd "$(dirname "$0")"

APP=build/Cordelia.app
rm -rf build
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

swiftc -O -swift-version 5 -target "$(uname -m)-apple-macos13.0" \
    -o "$APP/Contents/MacOS/Cordelia" Sources/*.swift
cp Info.plist "$APP/Contents/Info.plist"

# The icon is drawn by the app itself from the symbol the menu bar shows.
"$APP/Contents/MacOS/Cordelia" --make-iconset build/AppIcon.iconset
iconutil -c icns build/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"

# Signed for this Mac only. There is no developer identity behind it.
codesign --force --sign - "$APP"
echo "built $APP ($("$APP/Contents/MacOS/Cordelia" --version))"
