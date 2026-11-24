#!/bin/bash
set -euo pipefail
umask 077
temp=$(mktemp -d "$RUNNER_TEMP/signing.XXXXXX")
keychain="$temp/release.keychain-db"
password=$(openssl rand -hex 24)
security create-keychain -p "$password" "$keychain"
security set-keychain-settings -lut 7200 "$keychain"
security unlock-keychain -p "$password" "$keychain"
printf '%s' "${SIGNING_P12:?}" | base64 -D >"$temp/signing.p12"
security import "$temp/signing.p12" -k "$keychain" -P "${P12_PASSWORD:?}" -T /usr/bin/codesign -T /usr/bin/productbuild -T /usr/bin/productsign >/dev/null
security set-key-partition-list -S apple-tool:,apple: -s -k "$password" "$keychain" >/dev/null
security list-keychains -d user -s "$keychain" "$HOME/Library/Keychains/login.keychain-db"
printf '%s' "${ASC_PRIVATE_KEY:?}" >"$temp/api.p8"
printf 'ASC_KEY_PATH=%s\n' "$temp/api.p8" >>"$GITHUB_ENV"
if [[ -n ${STORE_PROFILE:-} ]]; then
    printf '%s' "$STORE_PROFILE" | base64 -D >"$temp/profile"
    security cms -D -i "$temp/profile" -o "$temp/profile.plist"
    uuid=$(plutil -extract UUID raw "$temp/profile.plist")
    directory="$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles"
    mkdir -p "$directory"
    cp "$temp/profile" "$directory/$uuid.provisionprofile"
    printf 'STORE_PROFILE_UUID=%s\n' "$uuid" >>"$GITHUB_ENV"
fi
