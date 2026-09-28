#!/bin/sh
set -eu
app=$1
output=$2
mkdir -p "$(dirname "$output")"
env -u TYPEFACEOFF_TESTING TYPEFACEOFF_STARTUP_PROFILE=1 \
    "$app/Contents/MacOS/TypefaceOff" -ApplePersistenceIgnoreState YES >"$output.launch.log" 2>&1 &
app_pid=$!
cleanup() {
    kill "$app_pid" 2>/dev/null || true
    wait "$app_pid" 2>/dev/null || true
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' HUP TERM
# Let exec finish before sample requests its task port. Use the PID because other worktrees
# can have apps with the same executable name and bundle identifier.
sleep 0.05
/usr/bin/sample "$app_pid" 2 1 -file "$output"
test -s "$output"
