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
