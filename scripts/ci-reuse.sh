#!/bin/sh
set -eu

# A branch run of the same tree already ran this workflow on GitHub-hosted runners,
# so a main run would only repeat it. Runner images change, so only a recent
# result stands in for main's.

tree=${1:?tree id required}
gate_job="Reuse a passing branch run"
max_age_seconds=86400
now=$(date +%s)

runs=$(gh api "repos/$GITHUB_REPOSITORY/actions/workflows/ci.yml/runs?event=push&status=success&per_page=100")
run=$(printf '%s\n' "$runs" |
    jq -r --arg tree "$tree" --argjson now "$now" --argjson max_age "$max_age_seconds" '
        first(.workflow_runs[]
            | select(.head_branch != "main"
                and .head_commit.tree_id == $tree
                and (.updated_at | fromdateiso8601) > $now - $max_age))
        | .id')

reused=false
if [ -n "$run" ]; then
    jobs=$(gh api "repos/$GITHUB_REPOSITORY/actions/runs/$run/jobs?per_page=100")
    status=0
    printf '%s\n' "$jobs" |
        jq -e --arg gate "$gate_job" '
            [.jobs[] | select(.name != $gate)]
            | length > 0
                and all(.conclusion == "success" and .runner_group_name == "GitHub Actions")' \
            >/dev/null || status=$?
    case $status in
    0)
        reused=true
        echo "Run $run already passed tree $tree"
        ;;
    1) echo "Run $run tested tree $tree, but not every job passed on a GitHub-hosted runner" ;;
    *) exit "$status" ;;
    esac
fi
echo "reused=$reused" >>"$GITHUB_OUTPUT"
