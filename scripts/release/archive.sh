#!/bin/bash
set -euo pipefail

mode=$1
archive=$2
shift 2
args=("$@")
case "$mode" in
ci-archive) args+=(CODE_SIGNING_ALLOWED=NO) ;;
archive | developer-id-archive)
    version=$(tools/gitcalver.sh --prefix 0.)
    args+=("MARKETING_VERSION=$version" "CURRENT_PROJECT_VERSION=${version#0.}" "TYPEFACEOFF_RELEASE_VERSION=$version")
    if [[ -n ${APPLE_TEAM_ID:-} ]]; then args+=("DEVELOPMENT_TEAM=$APPLE_TEAM_ID"); fi
    if [[ $mode == developer-id-archive ]]; then
        args+=(CODE_SIGN_STYLE=Manual "CODE_SIGN_IDENTITY=${DEVELOPER_ID_IDENTITY:-Developer ID Application}"
            TYPEFACEOFF_ENTITLEMENTS=Config/TypefaceOff.entitlements OTHER_CODE_SIGN_FLAGS=--timestamp)
    elif [[ -n ${STORE_PROFILE_UUID:-} ]]; then
        args+=(CODE_SIGN_STYLE=Manual "CODE_SIGN_IDENTITY=Apple Distribution" "TYPEFACEOFF_PROFILE=$STORE_PROFILE_UUID")
    else
        args+=(-allowProvisioningUpdates)
    fi
    ;;
*) exit 2 ;;
esac
rm -rf "$archive"
xcodebuild "${args[@]}" archive
