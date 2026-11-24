#!/bin/bash
set -euo pipefail

fail() {
    echo "github.sh: $1" >&2
    exit 1
}

operation=${1:?}
version=$(tools/gitcalver.sh --prefix 0.)
tag="v$version"
revision=$(git rev-parse HEAD)
repo=${GITHUB_REPOSITORY:?}
assets=.build/developer-id/assets
releases=$(gh api --paginate --slurp "repos/$repo/releases?per_page=100")
release=$(jq -c --arg tag "$tag" 'flatten[] | select(.tag_name == $tag)' <<<"$releases")
work=$(mktemp -d "${TMPDIR:-/tmp}/typefaceoff-github.XXXXXX")
trap 'rm -rf "$work"' EXIT
if [[ -n $release && $(jq .draft <<<"$release") == false ]]; then
    jq -e '.immutable and (.prerelease | not)' <<<"$release" >/dev/null || fail "release $tag is mutable or a prerelease; enable immutable releases before publishing"
    [[ $(gh api "repos/$repo/commits/$tag" --jq .sha) == "$revision" ]] || fail "tag $tag does not point at $revision"
    jq -e --arg name "TypefaceOff-$version.dmg" '
        [.assets[] | select(.state == "uploaded" and (.digest | test("^sha256:[a-f0-9]{64}$"))) | .name] |
        sort == ([$name, "SHA256SUMS", "release.json", "TypefaceOff.spdx.json"] | sort)' <<<"$release" >/dev/null || fail "release $tag lacks exactly its four verified assets"
    gh release download "$tag" --repo "$repo" --pattern release.json --dir "$work"
    jq -e --arg version "$version" --arg revision "$revision" '.version == $version and .revision == $revision' "$work/release.json" >/dev/null || fail "release.json of $tag does not name $version at $revision"
    gh release download "$tag" --repo "$repo" --pattern SHA256SUMS --dir "$work"
    for name in "TypefaceOff-$version.dmg" TypefaceOff.spdx.json; do
        hash=$(awk -v name="$name" '$2 == name { print $1 }' "$work/SHA256SUMS")
        [[ $hash =~ ^[0-9a-f]{64}$ ]] || fail "SHA256SUMS of $tag has no hash for $name"
        jq -e --arg name "$name" --arg digest "sha256:$hash" 'any(.assets[]; .name == $name and .digest == $digest)' <<<"$release" >/dev/null || fail "digest of $name in release $tag differs from SHA256SUMS"
    done
    if [[ $operation == inspect ]]; then echo 'published=true' >>"$GITHUB_OUTPUT"; fi
    exit 0
fi
if [[ $operation == inspect ]]; then
    echo 'published=false' >>"$GITHUB_OUTPUT"
    exit 0
fi
[[ $operation == publish ]] || fail "unknown operation $operation"
refs=$(gh api "repos/$repo/git/matching-refs/tags/$tag")
if jq -e --arg ref "refs/tags/$tag" 'any(.[]; .ref == $ref)' <<<"$refs" >/dev/null; then
    [[ $(gh api "repos/$repo/commits/$tag" --jq .sha) == "$revision" ]] || fail "tag $tag exists at another commit than $revision"
fi
if [[ -n $release ]]; then
    [[ $(jq -r .target_commitish <<<"$release") == "$revision" ]] || fail "draft release $tag targets another commit than $revision"
    jq -e --arg dmg "TypefaceOff-$version.dmg" '
        [.assets[].name] - [$dmg, "TypefaceOff.spdx.json", "SHA256SUMS", "release.json"] | length == 0' <<<"$release" >/dev/null || fail "draft release $tag has unexpected assets"
else
    gh release create "$tag" --repo "$repo" --draft --target "$revision" --title "Typeface/Off $version" --generate-notes
fi
(
    cd "$assets"
    shasum -a 256 -c SHA256SUMS
    jq -n --arg version "$version" --arg revision "$revision" '{version:$version, revision:$revision}' >release.json
    gh release upload "$tag" --repo "$repo" --clobber "TypefaceOff-$version.dmg" TypefaceOff.spdx.json SHA256SUMS release.json
)
draft=$(gh release view "$tag" --repo "$repo" --json isDraft,assets)
jq -e '.isDraft and (.assets | length == 4)' <<<"$draft" >/dev/null || fail "draft release $tag does not hold exactly four assets"
for file in "$assets"/{TypefaceOff-"$version".dmg,TypefaceOff.spdx.json,SHA256SUMS,release.json}; do
    hash=$(shasum -a 256 "$file" | cut -d ' ' -f 1)
    jq -e --arg name "${file##*/}" --arg digest "sha256:$hash" 'any(.assets[]; .name == $name and .digest == $digest)' <<<"$draft" >/dev/null || fail "uploaded ${file##*/} differs from the local copy"
done
latest=$(jq -r --arg version "$version" '
    def numbers: split(".") | map(tonumber);
    flatten | all(.[] | select((.draft or .prerelease) | not) |
        .tag_name | select(test("^v0\\.[0-9]{8}\\.[1-9][0-9]*$")) | ltrimstr("v") | numbers; . <= ($version | numbers))' <<<"$releases")
gh release edit "$tag" --repo "$repo" --draft=false --latest="$latest"
bash "$0" verify
