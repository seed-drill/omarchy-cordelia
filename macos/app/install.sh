#!/bin/bash
# Builds the app, puts it in ~/Applications, and starts it now and at every
# login. Run it again after `git pull` to update. Remove with ./uninstall.sh.
set -euo pipefail
cd "$(dirname "$0")"
./build.sh

LABEL=ai.seeddrill.cordelia.menubar
DEST="${HOME:?}/Applications/Cordelia.app"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"

# Stop the copy that is running, however it was started.
launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
pkill -f "Cordelia.app/Contents/MacOS/Cordelia" 2>/dev/null || true

mkdir -p "$HOME/Applications" "$HOME/Library/LaunchAgents"
rm -rf "$DEST"
cp -R build/Cordelia.app "$DEST"

# Started at login, and again if it crashes. Quit from the menu stays quit
# until the next login.
cat > "$PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$LABEL</string>
    <key>ProgramArguments</key>
    <array>
        <string>$DEST/Contents/MacOS/Cordelia</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <dict>
        <key>SuccessfulExit</key>
        <false/>
    </dict>
    <key>LimitLoadToSessionType</key>
    <string>Aqua</string>
    <key>ProcessType</key>
    <string>Interactive</string>
</dict>
</plist>
PLIST
launchctl bootstrap "gui/$(id -u)" "$PLIST"

# The earlier SwiftBar plugin would put a second icon beside this one.
LINK="$HOME/.swiftbar/cordelia.10s.py"
if [ -L "$LINK" ]; then
    rm "$LINK"
    echo "Removed the SwiftBar plugin link ($LINK). Quit SwiftBar if nothing else uses it."
fi
echo "Cordelia is in the menu bar, from $DEST."
