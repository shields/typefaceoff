#!/bin/bash
set -euo pipefail

signed=true
if [[ $1 == --unsigned ]]; then
    signed=false
    shift
fi
archive=$1
output=$2
app="$archive/Products/Applications/TypefaceOff.app"
info="$app/Contents/Info.plist"
version=$(plutil -extract CFBundleShortVersionString raw "$info")
name="TypefaceOff-$version.dmg"
mkdir -p "$output"
work=$(mktemp -d "$output/build.XXXXXX")
trap 'rm -rf "$work"' EXIT
mkdir "$work/root"
ditto "$app" "$work/root/TypefaceOff.app"
ln -s /Applications "$work/root/Applications"
for arch in arm64 x86_64; do lipo "$app/Contents/MacOS/TypefaceOff" -verify_arch "$arch"; done
[[ $(plutil -extract CFBundleIdentifier raw "$info") == com.typefaceoff ]]
if "$signed"; then
    [[ $version =~ ^0\.[0-9]{8}\.[1-9][0-9]*$ ]]
    [[ $(plutil -extract CFBundleVersion raw "$info") == "${version#0.}" ]]
    [[ $(plutil -extract TypefaceOffDisplayVersion raw "$info") == "$version" ]]
    identity=${DEVELOPER_ID_IDENTITY:-Developer ID Application}
    codesign --verify --deep --strict -R='anchor apple generic and certificate leaf[field.1.2.840.113635.100.6.1.13] exists' "$app"
fi
hdiutil create -quiet -fs HFS+ -format UDZO -volname TypefaceOff -srcfolder "$work/root" "$work/$name"
if "$signed"; then
    codesign --sign "$identity" --timestamp --identifier com.typefaceoff.dmg "$work/$name"
    if [[ -n ${ASC_KEY_PATH:-} ]]; then
        auth=(--key "$ASC_KEY_PATH" --key-id "${ASC_KEY_ID:?}" --issuer "${ASC_ISSUER_ID:?}")
    else
        auth=(--keychain-profile "${NOTARY_PROFILE:-typefaceoff-notary}")
    fi
    xcrun notarytool submit "$work/$name" "${auth[@]}" --wait --output-format json >"$work/notary.json"
    if ! jq -e '.status == "Accepted"' "$work/notary.json" >/dev/null; then
        jq '{id,status,message}' "$work/notary.json" >&2
        exit 1
    fi
    xcrun stapler staple "$work/$name"
    xcrun stapler validate "$work/$name"
    spctl --assess --type open --context context:primary-signature "$work/$name"
fi
hdiutil attach -readonly -nobrowse -mountpoint "$work/mounted" "$work/$name"
trap 'hdiutil detach "$work/mounted"; rm -rf "$work"' EXIT
[[ $(readlink "$work/mounted/Applications") == /Applications ]]
diff -qr "$work/root/TypefaceOff.app" "$work/mounted/TypefaceOff.app"
hdiutil detach "$work/mounted"
trap 'rm -rf "$work"' EXIT
cp "$archive/TypefaceOff.spdx.json" "$work/TypefaceOff.spdx.json"
(
    cd "$work"
    shasum -a 256 "$name" TypefaceOff.spdx.json >SHA256SUMS
)
for asset in "$name" TypefaceOff.spdx.json SHA256SUMS; do mv "$work/$asset" "$output/"; done
