#!/bin/bash
set -euo pipefail

start=${RELEASE_START_SHA:?}
[[ $start =~ ^[0-9a-f]{40}$ ]]
git rev-list --first-parent HEAD >"$RUNNER_TEMP/main-commits"
grep -Fxq "$start" "$RUNNER_TEMP/main-commits"
channels=(dmg store tap)
done_channels=" "
declare -a next=("" "" "")
while read -r sha; do
    statuses=$(gh api "repos/$GITHUB_REPOSITORY/commits/$sha/status" --jq '.statuses | map(if .state == "success" then .context elif .context == "release/store" and .state == "failure" then "store-rejected" else empty end)')
    for channel in "${channels[@]}"; do
        if jq -e --arg name "release/$channel" 'index($name) != null' <<<"$statuses" >/dev/null; then done_channels+="$channel "; fi
    done
    if [[ $done_channels == *" dmg "* && $done_channels == *" store "* && $done_channels == *" tap "* ]]; then break; fi
    runs=$(gh api "repos/$GITHUB_REPOSITORY/actions/runs?branch=main&event=push&head_sha=$sha&per_page=100")
    state=$(jq -er -f scripts/release/checks.jq <<<"$runs")
    for i in "${!channels[@]}"; do
        channel=${channels[i]}
        if [[ $done_channels == *" $channel "* ]]; then continue; fi
        case "$state" in
        ready)
            if [[ $channel == store ]] && jq -e 'index("store-rejected") != null' <<<"$statuses" >/dev/null; then continue; fi
            if [[ $channel == tap ]] && ! jq -e 'index("release/dmg") != null' <<<"$statuses" >/dev/null; then continue; fi
            next[i]=$sha
            ;;
        pending) next[i]="" ;;
        esac
    done
    if [[ $sha == "$start" ]]; then break; fi
done <"$RUNNER_TEMP/main-commits"
for i in "${!channels[@]}"; do printf '%s=%s\n' "${channels[i]}" "${next[i]}"; done >>"$GITHUB_OUTPUT"
