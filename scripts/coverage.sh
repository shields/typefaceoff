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
# Ask SwiftPM for the active build layout instead of picking a possibly stale bundle.
bin=$(swift build "$@" --show-bin-path)
coverage=$(swift test "$@" --show-codecov-path)
profile="$(dirname "$coverage")/default.profdata"
core=
for name in TypefaceCoreTests TypefaceOffPackageTests; do
    binary="$bin/$name.xctest/Contents/MacOS/$name"
    if test -x "$binary"; then
        core=$binary
        break
    fi
done
test -n "$core"
test -f "$profile"

# Xcode's app-hosted tests cover SwiftUI's window lifecycle.
app=.build/xcode/Build/Products/Debug/TypefaceOff.app/Contents/MacOS/TypefaceOff
if test -f "$app.debug.dylib"; then
    app="$app.debug.dylib"
fi
set -- "$profile"
for native in .build/xcode/Build/ProfileData/*/Coverage.profdata; do
    test -f "$native"
    set -- "$@" "$native"
done
test "$#" -gt 1
mkdir -p .build/coverage
profile=.build/coverage/all.profdata
xcrun llvm-profdata merge "$@" -o "$profile"
# Xcode and SwiftPM can spell the same worktree path differently (/tmp and
# /private/tmp). Exclude tests instead of filtering by the current absolute path.
exclude='/(Tests|\.build)/'
set -- "$core" -object "$app"
# Every SwiftPM test bundle has its own executable. Include tooling modules that
# are intentionally not linked into the font-engine test process.
tool="$bin/UIFuzzTests.xctest/Contents/MacOS/UIFuzzTests"
if ! test -x "$tool"; then
    echo "UIFuzzTests.xctest is missing from $bin, so UIFuzzSupport would go unmeasured." >&2
    exit 1
fi
set -- "$@" -object "$tool"
xcrun llvm-cov report "$@" -instr-profile="$profile" -ignore-filename-regex="$exclude"
report=.build/coverage/all-sources.json
xcrun llvm-cov export "$@" -instr-profile="$profile" -ignore-filename-regex="$exclude" >"$report"
if ! jq -e '
    [.data[].files[]] |
    any(.filename | contains("/Sources/TypefaceCore/")) and
    any(.filename | contains("/Sources/TypefaceOff/")) and
    any(.filename | contains("/Sources/UIFuzzSupport/")) and
    all(.summary.lines.covered == .summary.lines.count and
        .summary.regions.covered == .summary.regions.count and
        all(.segments[]; (.[3] | not) or .[2] < 9223372036854775807))
' "$report" >/dev/null; then
    echo "Coverage must include core, app, and fuzzing-support sources, with 100% line and region coverage for every file and no clamped execution counts." >&2
    jq -r '
        .data[].files[] | .filename as $file |
        .segments[] | select(.[3]) |
        if .[2] >= 9223372036854775807 then
            "\($file):\(.[0]):\(.[1]): execution count clamped by llvm-cov"
        elif .[2] == 0 and .[4] and (.[5] != true) then
            "\($file):\(.[0]):\(.[1]): uncovered region"
        else empty end
    ' "$report" >&2
    exit 1
fi
