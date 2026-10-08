#!/bin/bash
# Compares the menu the app would draw for each saved status with the menu it
# drew when the fixture was written. `run.sh --update` rewrites the expected
# files after a deliberate change; read the diff before committing it.
#
# A fixture is tests/fixtures/<name>.status.json. Beside it, if the case needs
# them: <name>.config.json for settings, and <name>.args for anything the
# status cannot say (--node-agent needs-approval). The home directory is
# /Users/alex.
set -uo pipefail
cd "$(dirname "$0")"
BIN=../build/Cordelia.app/Contents/MacOS/Cordelia
[ -x "$BIN" ] || { echo "build first: ../build.sh" >&2; exit 2; }
update=0; [ "${1:-}" = "--update" ] && update=1
fail=0; n=0
check() {   # a case's name, and what the app printed for it
    n=$((n + 1))
    if [ "$update" = 1 ]; then
        printf '%s\n' "$2" > "expected/$1.txt"
    elif ! diff -u "expected/$1.txt" <(printf '%s\n' "$2") > /dev/null 2>&1; then
        echo "FAIL $1"; diff -u "expected/$1.txt" <(printf '%s\n' "$2") | sed 's/^/    /'; fail=$((fail + 1))
    else
        echo "ok   $1"
    fi
}
for status in fixtures/*.status.json; do
    name=$(basename "$status" .status.json)
    config="fixtures/$name.config.json"; [ -f "$config" ] || config=/nonexistent/menubar.json
    extra=(); [ -f "fixtures/$name.args" ] && read -r -a extra < "fixtures/$name.args"
    got=$("$BIN" --dump-menu --status-file "$status" --config "$config" --home /Users/alex ${extra[@]+"${extra[@]}"})
    check "$name" "$got"
done
# "Add a Device" copies a command and runs nothing. The other device's key goes in only
# where the clipboard holds a key and nothing else, and never this device's own.
OTHER=cordelia_pk1studioqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqq
OWN=cordelia_pk1thismacqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqq
check add-device-key "$("$BIN" --dump-add-device --clipboard "  $OTHER
" --own "$OWN")"
check add-device-own "$("$BIN" --dump-add-device --clipboard "$OWN" --own "$OWN")"
check add-device-words "$("$BIN" --dump-add-device --clipboard "run this: $OTHER; rm -rf ~" --own "$OWN")"
check add-device-empty "$("$BIN" --dump-add-device --clipboard "" --own "$OWN")"
# The About window, which no saved status reaches: with a node to ask, and with none.
check about "$("$BIN" --dump-about --cli-version 0.2.0-alpha.9)"
check about-no-cli "$("$BIN" --dump-about --cli-version "")"
[ "$update" = 1 ] && { echo "wrote $n expected files"; exit 0; }
echo "$((n - fail)) of $n passed"
[ "$fail" = 0 ]
