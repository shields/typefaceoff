#!/bin/bash
set -euo pipefail

git rev-list --first-parent HEAD >"$RUNNER_TEMP/main-commits"
channels=(dmg store tap)
declare -a next=("" "" "")
open=" ${channels[*]} "
while [[ $open != " " ]] && read -r sha; do
    workflow=$(git ls-tree --name-only "$sha" -- .github/workflows/release.yml)
    [[ -n $workflow ]] || break
    status=$(gh api "repos/$GITHUB_REPOSITORY/commits/$sha/status?per_page=100")
    statuses=$(jq -c --arg sha "$sha" '(.total_count // error("status response for \($sha) lacks total_count")) as $total |
        if $total > (.statuses | length) then error("\($sha) has more statuses than one page") else
        [.statuses[] | select(.context | startswith("release/")) | {(.context | ltrimstr("release/")): .state}] | add // {} end' <<<"$status")
    jq -e 'type == "object"' <<<"$statuses" >/dev/null || {
        echo "queue.sh: unexpected status response for $sha: $statuses" >&2
        exit 1
    }
    state=""
    for i in "${!channels[@]}"; do
        channel=${channels[i]}
        if [[ $open != *" $channel "* ]]; then continue; fi
        if jq -e --arg channel "$channel" 'has($channel)' <<<"$statuses" >/dev/null; then
            open=${open/ $channel / }
            continue
        fi
        if [[ $channel == tap ]]; then
            if ! jq -e '.dmg == "success"' <<<"$statuses" >/dev/null; then continue; fi
            open=${open/ $channel / }
        fi
        if [[ -z $state ]]; then
            runs=$(gh api "repos/$GITHUB_REPOSITORY/actions/runs?branch=main&event=push&head_sha=$sha&per_page=100")
            state=$(jq -er -f scripts/release/checks.jq <<<"$runs") || {
                echo "queue.sh: cannot read the workflow runs of $sha" >&2
                exit 1
            }
        fi
        if [[ $state == ready ]]; then
            next[i]=$sha
            open=${open/ $channel / }
        fi
    done
done <"$RUNNER_TEMP/main-commits"
for i in "${!channels[@]}"; do printf '%s=%s\n' "${channels[i]}" "${next[i]}"; done >>"$GITHUB_OUTPUT"
