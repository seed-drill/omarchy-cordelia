#!/bin/bash
# Stops the menu bar app and removes it. The node and its data are untouched.
set -euo pipefail
LABEL=ai.seeddrill.cordelia.menubar
launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
pkill -f "Cordelia.app/Contents/MacOS/Cordelia" 2>/dev/null || true
rm -f "${HOME:?}/Library/LaunchAgents/$LABEL.plist"
rm -rf "${HOME:?}/Applications/Cordelia.app"
echo "Removed. Settings stay in ~/.config/cordelia/menubar.json."
