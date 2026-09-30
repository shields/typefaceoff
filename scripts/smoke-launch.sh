#!/bin/sh
# Launches an app and requires it to be running after a few seconds, so a binary that this macOS
# cannot load, or that crashes at launch, fails without any test runner.
set -eu
app=$1
"$app/Contents/MacOS/$(basename "$app" .app)" &
pid=$!
trap 'kill "$pid" 2>/dev/null || true; wait "$pid" 2>/dev/null || true' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
seconds=0
while [ "$seconds" -lt 15 ]; do
    sleep 1
    seconds=$((seconds + 1))
    if ! kill -0 "$pid" 2>/dev/null; then
        status=0
        wait "$pid" || status=$?
        echo "$app exited with status $status after $seconds seconds." >&2
        exit 1
    fi
done
