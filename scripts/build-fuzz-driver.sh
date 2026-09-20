#!/bin/sh
set -eu

source_executable=$1
driver_app=$2
contents="$driver_app/Contents"
executable="$contents/MacOS/ui-fuzz"

mkdir -p "$contents/MacOS"
install -m 755 "$source_executable" "$executable"
install -m 644 Config/UIFuzzDriver-Info.plist "$contents/Info.plist"
codesign --force --sign - --identifier dev.msrl.typefaceoff.ui-fuzz \
    --requirements '=designated => identifier "dev.msrl.typefaceoff.ui-fuzz"' \
    "$driver_app"
