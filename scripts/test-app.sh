#!/bin/sh
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
