#!/bin/sh
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
            [.jobs[] | select(.name != $gate and .name != "Dispatch release")]
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
