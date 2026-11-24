#!/bin/bash
set -euo pipefail
archive=$1
directory=$2
work=$(mktemp -d "${TMPDIR:-/tmp}/typefaceoff-export.XXXXXX")
trap 'rm -rf "$work"' EXIT
options=Config/TestFlight.plist
args=(-allowProvisioningUpdates)
if [[ -n ${STORE_PROFILE_UUID:-} ]]; then
    options="$work/options.plist"
    cp Config/TestFlight.plist "$options"
    plutil -replace signingStyle -string manual "$options"
    plutil -insert signingCertificate -string "Apple Distribution" "$options"
    plutil -insert installerSigningCertificate -string "Mac Installer Distribution" "$options"
    plutil -insert provisioningProfiles -dictionary "$options"
    /usr/libexec/PlistBuddy -c "Add :provisioningProfiles:com.typefaceoff string $STORE_PROFILE_UUID" "$options"
    plutil -insert teamID -string "${APPLE_TEAM_ID:?}" "$options"
    args=(-authenticationKeyPath "${ASC_KEY_PATH:?}" -authenticationKeyID "${ASC_KEY_ID:?}" -authenticationKeyIssuerID "${ASC_ISSUER_ID:?}")
fi
rm -rf "$directory"
PATH=/usr/bin:/bin:/usr/sbin:/sbin xcodebuild -exportArchive -archivePath "$archive" -exportPath "$directory" -exportOptionsPlist "$options" "${args[@]}"
