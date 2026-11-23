#!/bin/bash
# Copyright © 2026 Michael Shields
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

set -euo pipefail

app="$1/Products/Applications/TypefaceOff.app"
maps="$2/Build/Intermediates.noindex/ArchiveIntermediates/TypefaceOff/IntermediateBuildFilesPath/TypefaceOff.build/Release/TypefaceOff.build"
output=$3
info="$app/Contents/Info.plist"
binary="$app/Contents/MacOS/TypefaceOff"
resources="$app/Contents/Resources/TypefaceOff_TypefaceCore.bundle/Contents/Resources"
version=$(plutil -extract CFBundleShortVersionString raw "$info")
xcode_build=$(plutil -extract DTXcodeBuild raw "$info")
architectures=$(lipo -archs "$binary")

mkdir -p "$(dirname "$output")"
work=$(mktemp -d "$output.XXXXXX")
trap 'rm -rf "$work"' EXIT
for arch in $architectures; do
    awk '
        /^# Object files:/ {objects = 1; next}
        /^# Sections:/ {exit}
        !objects {next}
        / linker synthesized$/ || /\.tbd$/ {next}
        /\/IntermediateBuildFilesPath\/TypefaceOff.build\/Release\/TypefaceOff.build\/Objects-normal\// {next}
        /\/BuildProductsPath\/Release\/TypefaceCore\.o$/ {next}
        {sub(/^.*\//, ""); print}
        END {if (!objects) exit 1}
    ' \
        "$maps/TypefaceOff-LinkMap-normal-$arch.txt"
done >"$work/static"
sort -u "$work/static" -o "$work/static"
otool -arch all -L "$binary" | sed -nE 's/^[[:space:]]+(.*) \(compatibility version .*$/\1/p' | sort -u >"$work/dynamic"

SYFT_CACHE_DIR="$work/cache" SYFT_CHECK_FOR_APP_UPDATE=false SYFT_FILE_METADATA_SELECTION=all syft scan "dir:$app" \
    --override-default-catalogers directory,installed,file \
    --source-name TypefaceOff --source-version "$version" -o "spdx-json=$work/scan.json"
jq -e -L scripts -f scripts/app-sbom.jq \
    --arg xcode "$xcode_build" --rawfile static "$work/static" --rawfile dynamic "$work/dynamic" \
    --slurpfile catalog "$resources/languages.json" --rawfile frequencies "$resources/character-frequencies.tsv" \
    "$work/scan.json" >"$work/sbom.json"
mv "$work/sbom.json" "$output"
jq -ne --slurpfile scan "$work/scan.json" --slurpfile sbom "$output" '
    [$scan[0].packages[] | select((.name == "TypefaceOff" and
      (.SPDXID == "SPDXRef-DocumentRoot-Directory-TypefaceOff" or
       (.SPDXID | startswith("SPDXRef-Package-apple-app-bundle-")))) | not) | .name] +
    [$sbom[0].packages[] | select(.SPDXID | startswith("SPDXRef-Unreviewed-")) | .name] |
    if length > 0 then error("Review third-party attribution in NOTICE for: " + join(", ")) else true end
' >/dev/null
sh scripts/app-notice.sh "$resources" >"$work/NOTICE"
if ! cmp "$work/NOTICE" "$app/Contents/Resources/Acknowledgments.txt"; then
    echo "Archived acknowledgments differ from NOTICE and the bundled data revisions." >&2
    exit 1
fi
