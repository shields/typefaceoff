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

test_directory=$(mktemp -d "${TMPDIR:-/tmp}/typefaceoff-vm-teardown.XXXXXX")
trap 'rm -rf "$test_directory"' EXIT
fixture="$test_directory/teardown.sh"
sed -n '/^stop_vm() {$/,/^}$/p' "$(dirname "$0")/fuzz-vm.sh" >"$fixture"
cat >>"$fixture" <<'SH'
campaign_event() {
    printf 'event\n'
    if [ "$event_result" -ne 0 ]; then
        printf 'event write failed\n' >&2
    fi
    return "$event_result"
}
vm_ssh() { printf 'guest-stop\n'; }
tart() { printf 'vm-stop\n' >&2; }
kill() { printf 'kill %s\n' "$*"; }
wait() { printf 'wait %s\n' "$*"; }
observer_pid=111
tart_pid=222
ip=127.0.0.1
vm=test
stop_reason=completed
event_result=$2
trap stop_vm EXIT
exit "$1"
SH

for initial_status in 0 23 143; do
    for event_status in 0 73; do
        actual_status=0
        sh -eu "$fixture" "$initial_status" "$event_status" \
            >"$test_directory/stdout" 2>"$test_directory/stderr" || actual_status=$?
        expected_status=$initial_status
        if [ "$expected_status" -eq 0 ]; then expected_status=$event_status; fi
        if [ "$actual_status" -ne "$expected_status" ]; then
            echo "teardown returned $actual_status; expected $expected_status (exit=$initial_status, logging=$event_status)" >&2
            exit 1
        fi
        expected_output=$(printf 'kill 111\nwait 111\nevent\nkill -0 222\nguest-stop\nwait 222\n')
        if [ "$(cat "$test_directory/stdout")" != "$expected_output" ]; then
            echo "teardown did not stop and wait for both observer and VM (exit=$initial_status, logging=$event_status)" >&2
            cat "$test_directory/stdout" >&2
            exit 1
        fi
        expected_errors=vm-stop
        if [ "$event_status" -ne 0 ]; then
            expected_errors=$(printf 'event write failed\nvm-stop\n')
        fi
        if [ "$(cat "$test_directory/stderr")" != "$expected_errors" ]; then
            echo "teardown did not stop the VM or retain the logging error" >&2
            cat "$test_directory/stderr" >&2
            exit 1
        fi
    done
done
