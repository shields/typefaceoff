#!/bin/bash
set -euo pipefail
output=.build/app-store/screenshots
mkdir -p "$output"
work=$(mktemp -d .build/store-screenshots.XXXXXX)
trap 'rm -rf "$work"' EXIT
xcodebuild -quiet -project TypefaceOff.xcodeproj -scheme TypefaceOff -configuration Debug \
    -destination "platform=macOS,arch=$(uname -m)" -derivedDataPath "$work/xcode" \
    -parallel-testing-enabled NO CODE_SIGN_ENTITLEMENTS= TYPEFACEOFF_STORE_SCREENSHOTS=1 \
    "TYPEFACEOFF_REVIEW_DIR=/Volumes/My Shared Files/artifacts/review" build-for-testing
tar -cf "$work/products.tar" -C "$work/xcode/Build" Products
./scripts/vm.sh test "$@" "$PWD/$work/results" "$work/products.tar" TypefaceOffTests/ReviewScreens
for screen in text glyph-1440 languages; do
    file="$work/results/review/$screen.png"
    dimensions=$(sips -g pixelWidth -g pixelHeight "$file" | awk '/pixelWidth:|pixelHeight:/ {print $2}' | paste -sd x -)
    case "$dimensions" in
    1440x900 | 2880x1800) ;;
    *)
        echo "Unexpected Store screenshot size: $dimensions" >&2
        exit 1
        ;;
    esac
    if ! sips -g hasAlpha "$file" | grep -q 'hasAlpha: no$'; then
        echo "Store screenshot has an alpha channel: $screen" >&2
        exit 1
    fi
done
mv "$work/results/review"/{text,glyph-1440,languages}.png "$output/"
rm -f "$output"/{text,glyph-1440,languages}.jpg
