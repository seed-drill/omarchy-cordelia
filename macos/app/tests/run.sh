#!/bin/bash
# Compares the menu the app would draw for each saved status with the menu it
# drew when the fixture was written. `run.sh --update` rewrites the expected
# files after a deliberate change; read the diff before committing it.
#
# A fixture is tests/fixtures/<name>.status.json, with <name>.config.json
# beside it if the case needs settings. The home directory is /Users/alex.
set -uo pipefail
cd "$(dirname "$0")"
BIN=../build/Cordelia.app/Contents/MacOS/Cordelia
[ -x "$BIN" ] || { echo "build first: ../build.sh" >&2; exit 2; }
update=0; [ "${1:-}" = "--update" ] && update=1
fail=0; n=0
for status in fixtures/*.status.json; do
    name=$(basename "$status" .status.json)
    config="fixtures/$name.config.json"; [ -f "$config" ] || config=/nonexistent/menubar.json
    got=$("$BIN" --dump-menu --status-file "$status" --config "$config" --home /Users/alex)
    n=$((n + 1))
    if [ "$update" = 1 ]; then
        printf '%s\n' "$got" > "expected/$name.txt"
    elif ! diff -u "expected/$name.txt" <(printf '%s\n' "$got") > /dev/null 2>&1; then
        echo "FAIL $name"; diff -u "expected/$name.txt" <(printf '%s\n' "$got") | sed 's/^/    /'; fail=$((fail + 1))
    else
        echo "ok   $name"
    fi
done
[ "$update" = 1 ] && { echo "wrote $n expected files"; exit 0; }
echo "$((n - fail)) of $n passed"
[ "$fail" = 0 ]
