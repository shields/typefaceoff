#!/bin/bash
set -euo pipefail
version=$(tools/gitcalver.sh --prefix 0.)
tag="v$version"
release=$(GH_TOKEN="${SOURCE_TOKEN:?}" gh release view "$tag" -R shields/typefaceoff --json assets,isImmutable,isDraft)
digest=$(jq -er --arg name "TypefaceOff-$version.dmg" '
    select(.isImmutable and (.isDraft | not)) | .assets[] | select(.name == $name) |
    .digest | capture("^sha256:(?<hash>[0-9a-f]{64})$").hash' <<<"$release")
[[ $(GH_TOKEN="$SOURCE_TOKEN" gh api "repos/shields/typefaceoff/commits/$tag" --jq .sha) == "$(git rev-parse HEAD)" ]]
repo=shields/homebrew-tap
branch="release/typefaceoff-$version"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
git_auth() { git -c credential.helper= -c 'credential.helper=!gh auth git-credential' "$@"; }
git_auth clone -q "https://github.com/$repo.git" "$work/tap"
cask=Casks/typefaceoff.rb
sed -e "s/@VERSION@/$version/" -e "s/@SHA256@/$digest/" packaging/homebrew/typefaceoff.rb.in >"$work/cask"
cd "$work/tap"
if [[ -f $cask ]]; then
    current=$(sed -n 's/^  version "\([^"]*\)"$/\1/p' "$cask")
    [[ $current =~ ^0\.[0-9]{8}\.[1-9][0-9]*$ ]]
    if [[ $current == "$version" ]]; then
        cmp "$work/cask" "$cask"
        echo merged=true >>"$GITHUB_OUTPUT"
        exit 0
    fi
    if [[ $(printf '%s\n' "$version" "$current" | sort -V | tail -1) == "$current" ]]; then
        echo merged=true >>"$GITHUB_OUTPUT"
        exit 0
    fi
fi
if git show-ref --verify --quiet "refs/remotes/origin/$branch"; then
    commit=$(git rev-parse "origin/$branch")
    [[ $(git diff --name-only "origin/main...$commit") == "$cask" ]]
    git show "$commit:$cask" | cmp "$work/cask" -
else
    git switch -c "$branch"
    mkdir -p Casks
    cp "$work/cask" "$cask"
    git add "$cask"
    git -c user.name='shields-homebrew-tap[bot]' -c user.email='shields-homebrew-tap[bot]@users.noreply.github.com' commit -m "Update Typeface/Off to $version"
    commit=$(git rev-parse HEAD)
    git_auth push origin "HEAD:refs/heads/$branch"
fi
pr=$(gh pr list -R "$repo" --head "$branch" --base main --json number,isCrossRepository --jq '.[] | select(.isCrossRepository == false) | .number')
if [[ -z $pr ]]; then
    printf 'Install Typeface/Off %s from the notarized GitHub release at %s.\n' "$version" "$tag" >"$work/body"
    pr=$(gh pr create -R "$repo" --head "$branch" --base main --title "Update Typeface/Off to $version" --body-file "$work/body")
fi
if [[ $(gh pr view "$pr" -R "$repo" --json autoMergeRequest --jq '.autoMergeRequest == null') == true ]]; then
    gh pr merge "$pr" -R "$repo" --auto --squash --match-head-commit "$commit"
fi
