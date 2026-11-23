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
result=.build/TestResults.xcresult
rm -rf "$result"
status=0
xcodebuild "$@" -resultBundlePath "$result" || status=$?
if test "$status" -ne 0 && test -d "$result"; then
    # Quiet xcodebuild lists failing tests but omits their assertion messages.
    xcrun xcresulttool get test-results summary --path "$result" || true
fi
if test "$status" -eq 0; then
    # A test runner that cannot load the Swift Testing tests runs none and still succeeds.
    # Captured on its own so that set -e stops when xcresulttool fails; in a pipeline only jq's
    # status counts.
    summary=$(xcrun xcresulttool get test-results summary --path "$result")
    if ! printf '%s' "$summary" | jq -e '.totalTestCount > 0' >/dev/null; then
        echo "No tests ran." >&2
        status=1
    fi
fi
if test "$status" -eq 0; then
    # SwiftUI reports misuse, such as publishing changes during a view update, only as runtime
    # warnings, which leave the tests passing.
    warnings=$(xcrun xcresulttool get test-results tests --path "$result" | jq -r '
        paths(objects and .nodeType? == "Runtime Warning") as $path
        | getpath($path) as $warning
        | "\($warning.sourceLocation.filePath // "unknown"):\($warning.sourceLocation.lineNumber // 0): runtime warning in \(getpath($path[0:-2]).name): \($warning.name)"')
    if test -n "$warnings"; then
        echo "$warnings" >&2
        status=1
    fi
fi
exit "$status"
