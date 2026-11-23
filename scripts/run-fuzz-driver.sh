#!/bin/sh
# Copyright © 2026 Michael Shields
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

set -eu

driver_app=$1
shift
case $driver_app in
/*) ;;
*) driver_app="$PWD/$driver_app" ;;
esac
driver_pid=
opener_pid=
interrupted=0
wait_status=0
relay_directory=$(mktemp -d "${TMPDIR:-/tmp}/typefaceoff-ui-fuzz.XXXXXX")
stdout_pipe="$relay_directory/stdout"
stderr_pipe="$relay_directory/stderr"
mkfifo "$stdout_pipe" "$stderr_pipe"
cat "$stdout_pipe" &
stdout_relay_pid=$!
cat "$stderr_pipe" >&2 &
stderr_relay_pid=$!

# shellcheck disable=SC2329 # Invoked by the signal traps below.
forward_signal() {
    interrupted=1
    if [ -z "$driver_pid" ]; then
        driver_pid=$(pgrep -x ui-fuzz | tail -1 || true)
    fi
    if [ -n "$driver_pid" ] && kill -0 "$driver_pid" 2>/dev/null; then
        kill -TERM "$driver_pid"
    fi
}

trap forward_signal INT TERM
open -n -W -o "$stdout_pipe" --stderr "$stderr_pipe" \
    --env "TYPEFACEOFF_FUZZ_VM=${TYPEFACEOFF_FUZZ_VM:-0}" \
    --env "TYPEFACEOFF_FUZZ_VM_NAME=${TYPEFACEOFF_FUZZ_VM_NAME:-}" "$driver_app" --args "$@" &
opener_pid=$!

attempt=0
while [ "$attempt" -lt 200 ] && kill -0 "$opener_pid" 2>/dev/null; do
    driver_pid=$(pgrep -x ui-fuzz | tail -1 || true)
    [ -z "$driver_pid" ] || break
    attempt=$((attempt + 1))
    sleep 0.05
done

wait "$opener_pid" || wait_status=$?
trap - INT TERM
if [ "$interrupted" -eq 1 ]; then
    attempt=0
    while [ -n "$driver_pid" ] && kill -0 "$driver_pid" 2>/dev/null &&
        [ "$attempt" -lt 400 ]; do
        attempt=$((attempt + 1))
        sleep 0.1
    done
    if [ -n "$driver_pid" ] && kill -0 "$driver_pid" 2>/dev/null; then
        kill -KILL "$driver_pid"
    fi
    if kill -0 "$opener_pid" 2>/dev/null; then
        kill -TERM "$opener_pid"
    fi
    wait "$opener_pid" 2>/dev/null || true
fi
kill "$stdout_relay_pid" "$stderr_relay_pid" 2>/dev/null || true
wait "$stdout_relay_pid" "$stderr_relay_pid" 2>/dev/null || true
rm -rf "$relay_directory"
if [ "$interrupted" -eq 1 ]; then
    exit 130
fi
exit "$wait_status"
