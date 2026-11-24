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

script="$(cd "$(dirname "$0")" && pwd)/ci-reuse.sh"
workflow="$(dirname "$script")/../.github/workflows/ci.yml"
gate=$(awk '$0 == "  reuse:" { in_job = 1; next } in_job && sub(/^    name: /, "") { print; exit }' "$workflow")
if [ -z "$gate" ]; then
    echo "no name for the reuse job in $workflow" >&2
    exit 1
fi
test_directory=$(mktemp -d "${TMPDIR:-/tmp}/typefaceoff-ci-reuse.XXXXXX")
trap 'rm -rf "$test_directory"' EXIT
mkdir "$test_directory/bin"
cat >"$test_directory/bin/gh" <<'SH'
#!/bin/sh
[ "$1" = api ] || exit 64
case $2 in
'repos/shields/typefaceoff/actions/workflows/ci.yml/runs?event=push&status=success&per_page=100') endpoint=runs ;;
'repos/shields/typefaceoff/actions/runs/7/jobs?per_page=100') endpoint=jobs ;;
*)
    echo "unexpected request: $2" >&2
    exit 65
    ;;
esac
cat "$FIXTURES/$endpoint.json"
[ "$endpoint" != "$GH_FAIL" ]
SH
chmod +x "$test_directory/bin/gh"

failing_endpoint="none"
recent=$(jq -nr 'now - 3600 | todate')
stale=$(jq -nr 'now - 90000 | todate')

write_runs() {
    jq -n --arg branch "$1" --arg tree "$2" --arg updated "$3" \
        '{workflow_runs: [
            {id: 9, head_branch: "main", head_commit: {tree_id: "tested"}, updated_at: $updated},
            {id: 7, head_branch: $branch, head_commit: {tree_id: $tree}, updated_at: $updated}]}' \
        >"$test_directory/runs.json"
}

write_jobs() {
    jq -n --arg gate "$gate" --arg conclusion "$1" --arg group "$2" \
        '{jobs: [
            {name: $gate, conclusion: "skipped", runner_group_name: null},
            {name: "Dispatch release", conclusion: "skipped", runner_group_name: null},
            {name: "Build, lint, and test", conclusion: "success", runner_group_name: "GitHub Actions"},
            {name: "Test on macOS 15", conclusion: $conclusion, runner_group_name: $group}]}' \
        >"$test_directory/jobs.json"
}

expect() {
    expected=$1
    description=$2
    : >"$test_directory/output"
    actual_status=0
    PATH="$test_directory/bin:$PATH" FIXTURES="$test_directory" GH_FAIL=$failing_endpoint \
        GITHUB_REPOSITORY=shields/typefaceoff GITHUB_OUTPUT="$test_directory/output" \
        sh "$script" "${3-tested}" >"$test_directory/stdout" 2>&1 || actual_status=$?
    if [ "$expected" = failure ]; then
        if [ "$actual_status" -eq 0 ]; then
            echo "$description: expected failure, got $(cat "$test_directory/output")" >&2
            exit 1
        fi
        return
    fi
    if [ "$actual_status" -ne 0 ]; then
        echo "$description: exited $actual_status" >&2
        cat "$test_directory/stdout" >&2
        exit 1
    fi
    actual=$(cat "$test_directory/output")
    if [ "$actual" != "reused=$expected" ]; then
        echo "$description: expected reused=$expected, got $actual" >&2
        exit 1
    fi
}

write_jobs success "GitHub Actions"
write_runs renovate/deps tested "$recent"
expect true "recent passing branch run of the same tree"
write_runs renovate/deps other "$recent"
expect false "branch run of another tree"
write_runs main tested "$recent"
expect false "only main runs of the same tree"
write_runs renovate/deps tested "$stale"
expect false "stale branch run"

write_runs renovate/deps tested "$recent"
write_jobs skipped "GitHub Actions"
expect false "skipped job"
write_jobs failure "GitHub Actions"
expect false "failed job"
write_jobs success "Self-hosted"
expect false "self-hosted job"
jq -n --arg gate "$gate" \
    '{jobs: [{name: $gate, conclusion: "success", runner_group_name: "GitHub Actions"}]}' \
    >"$test_directory/jobs.json"
expect false "no jobs besides the gate"

write_jobs success "GitHub Actions"
failing_endpoint="runs"
expect failure "failed runs request"
failing_endpoint="jobs"
expect failure "failed jobs request"
failing_endpoint="none"
expect failure "empty tree" ""
echo '{"jobs": "unexpected"}' >"$test_directory/jobs.json"
expect failure "malformed jobs response"
