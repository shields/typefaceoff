#!/bin/sh
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
xcrun llvm-cov report "$core" -object "$app" -instr-profile="$profile" Sources
report=.build/coverage/all-sources.json
xcrun llvm-cov export "$core" -object "$app" -instr-profile="$profile" Sources >"$report"
if ! jq -e '
    [.data[].files[].summary.lines] |
    length > 0 and all(.covered == .count)
' "$report" >/dev/null; then
    echo "Swift line coverage must be 100% for every source file." >&2
    exit 1
fi
