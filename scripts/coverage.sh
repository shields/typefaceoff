#!/bin/sh
set -eu
# Swift 6.3 and 6.4 use different build layouts. Locate the core test bundle.
profile=$(find .build -path '*/codecov/default.profdata' -type f -print -quit)
binary=$(find .build -path '*/TypefaceCoreTests.xctest/Contents/MacOS/*' -type f -print -quit)
if test -z "$binary"; then
    binary=$(find .build -path '*PackageTests.xctest/Contents/MacOS/*' -type f -print -quit)
fi
test -n "$profile"
test -n "$binary"
xcrun llvm-cov report "$binary" -instr-profile="$profile" Sources/TypefaceCore
