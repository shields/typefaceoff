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
exit "$status"
