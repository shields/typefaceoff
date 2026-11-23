#!/bin/bash
set -euo pipefail
: "${STORE_PROFILE_UUID:?}" "${ASC_KEY_PATH:?}" "${ASC_KEY_ID:?}" "${ASC_ISSUER_ID:?}" "${ASC_APP_ID:?}"
version=$(tools/gitcalver.sh --prefix 0.)
swiftc scripts/release/store-state.swift -o "$RUNNER_TEMP/store-state"
state() { "$RUNNER_TEMP/store-state" "${version#0.}" <"${ASC_KEY_PATH:?}"; }
status=$(state)
case "$status" in
ABSENT | FAILED | INVALID) make testflight ;;
PROCESSING | VALID) ;;
*)
    echo "Unknown App Store Connect build status: $status" >&2
    exit 1
    ;;
esac
for ((attempt = 0; attempt < 60; attempt++)); do
    status=$(state)
    case "$status" in
    VALID) exit 0 ;;
    ABSENT | PROCESSING) sleep 30 ;;
    FAILED | INVALID)
        echo rejected=true >>"$GITHUB_OUTPUT"
        echo "Apple rejected build $version: $status" >&2
        exit 1
        ;;
    *)
        echo "App Store Connect build $version: $status" >&2
        exit 1
        ;;
    esac
done
echo "Timed out waiting for App Store Connect build $version" >&2
exit 1
