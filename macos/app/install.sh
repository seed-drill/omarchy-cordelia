#!/bin/bash
# Builds the app, puts it in ~/Applications, and opens it now and at every
# login. Run it again after `git pull` to update. Remove with ./uninstall.sh.
set -euo pipefail
cd "$(dirname "$0")"
./build.sh

LABEL=ai.seeddrill.cordelia.menubar
DEST="${HOME:?}/Applications/Cordelia.app"

# Stop the copy that is running, and retire the launch agent that the first
# version of this script installed.
launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
rm -f "$HOME/Library/LaunchAgents/$LABEL.plist"
pkill -f "Cordelia.app/Contents/MacOS/Cordelia" 2>/dev/null || true

mkdir -p "$HOME/Applications"
rm -rf "$DEST"
cp -R build/Cordelia.app "$DEST"

# A login item of its own: macOS lists it under "Open at Login" by name and
# icon, apart from the node's background item. Quit from the menu stays quit
# until the next login.
if ! "$DEST/Contents/MacOS/Cordelia" --login-item on; then
    echo "Add it by hand: System Settings > General > Login Items > Open at Login." >&2
fi
open -g "$DEST"

# The earlier SwiftBar plugin would put a second icon beside this one.
LINK="$HOME/.swiftbar/cordelia.10s.py"
if [ -L "$LINK" ]; then
    rm "$LINK"
    echo "Removed the SwiftBar plugin link ($LINK). Quit SwiftBar if nothing else uses it."
fi
echo "Cordelia is in the menu bar, from $DEST."
