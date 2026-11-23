#!/bin/bash
set -euo pipefail
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
output=.build/app-store/screenshots
xcodebuild -quiet -project TypefaceOff.xcodeproj -scheme TypefaceOff -configuration Debug \
    -destination "platform=macOS,arch=$(uname -m)" -derivedDataPath "$work/xcode" \
    -parallel-testing-enabled NO CODE_SIGN_ENTITLEMENTS= TYPEFACEOFF_STORE_SCREENSHOTS=1 \
    "TYPEFACEOFF_REVIEW_DIR=$work/review" -only-testing:TypefaceOffTests/ReviewScreens test
mkdir -p "$output"
for screen in text glyph-1440 languages; do
    test -s "$work/review/$screen.png"
    sips -s format jpeg -s formatOptions best "$work/review/$screen.png" --out "$work/$screen.jpg"
    dimensions=$(sips -g pixelWidth -g pixelHeight "$work/$screen.jpg" | awk '/pixelWidth:|pixelHeight:/ {print $2}' | paste -sd x -)
    case "$dimensions" in
    1440x900 | 2880x1800) ;;
    *)
        echo "Unexpected Store screenshot size: $dimensions" >&2
        exit 1
        ;;
    esac
done
mv "$work"/{text,glyph-1440,languages}.jpg "$output/"
