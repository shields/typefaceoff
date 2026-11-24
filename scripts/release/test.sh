#!/bin/bash
set -euo pipefail
root=$(pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/typefaceoff-release-test.XXXXXX")
trap 'rm -rf "$work"' EXIT
# Distinct commit dates order a walk without --first-parent so that it visits the merged branch's commit.
clock=1700000000
tick() {
    clock=$((clock + 60))
    export GIT_AUTHOR_DATE="$clock +0000" GIT_COMMITTER_DATE="$clock +0000"
}
git init -q -b main "$work/repo"
cd "$work/repo"
git config user.name test
git config user.email test@example.invalid
tick
mkdir -p .github/workflows
touch .github/workflows/ci.yml
git add .github
git commit -q -m 'Before releases'
git switch -qc distribution
mkdir -p scripts/release
touch .github/workflows/release.yml
cp "$root/scripts/release/checks.jq" scripts/release/
git add scripts .github
tick
git commit -qm 'Add release workflow'
git switch -q main
tick
git merge -q --no-ff distribution -m first
for commit in second third fourth; do
    tick
    git commit -q --allow-empty -m "$commit"
done
export GITHUB_REPOSITORY=example/test RUNNER_TEMP="$work" GITHUB_OUTPUT="$work/output" CALLS="$work/calls"
first=$(git rev-parse HEAD~3)
second=$(git rev-parse HEAD~2)
third=$(git rev-parse HEAD~1)
fourth=$(git rev-parse HEAD)
by_commit() { jq -nc '[$ARGS.positional[] | capture("^(?<sha>[0-9a-f]+)=(?<value>.+)$")] | group_by(.sha) | map({key: .[0].sha, value: map(.value)}) | from_entries' --args "$@"; }
cat >"$work/gh" <<'MOCK'
#!/bin/bash
set -euo pipefail
echo "$2" >>"$CALLS"
[[ $1 == api ]] || exit 3
case $2 in
"repos/$GITHUB_REPOSITORY/commits/"*"/status?per_page=100")
    [[ $# -eq 2 ]] || exit 3
    [[ ${MOCK_FAIL:-} != status ]] || exit 1
    [[ ${MOCK_FAIL:-} != status-body ]] || {
        echo '[]'
        exit 0
    }
    sha=${2%/status\?per_page=100}
    jq -n --arg sha "${sha##*/}" --argjson statuses "$MOCK_STATUSES" '
        ($statuses[$sha] // [] | map(split(":") | {state: .[0], context: .[1]})) as $release |
        [{state: "failure", context: "ci/other"}, {state: "success", context: "dmg"}, {state: "success", context: "store"}, {state: "success", context: "tap"}, {state: "error", context: "ci/release/dmg"}] as $other |
        {statuses: ($release + $other)} | .total_count = (.statuses | length) + (if env.MOCK_FAIL == "status-overflow" then 1 else 0 end)'
    ;;
"repos/$GITHUB_REPOSITORY/actions/runs?branch=main&event=push&head_sha="*"&per_page=100")
    [[ $# -eq 2 ]] || exit 3
    [[ ${MOCK_FAIL:-} != runs ]] || exit 1
    [[ ${MOCK_FAIL:-} != runs-body ]] || {
        echo '{}'
        exit 0
    }
    sha=${2##*head_sha=}
    sha=${sha%%&*}
    jq -n --arg sha "$sha" --argjson outcomes "$MOCK_OUTCOMES" '($outcomes[$sha][0] // "success") as $outcome |
        {workflow_runs: (if $outcome == "absent" then [] else ["ci", "actions-lock", "zizmor"] | map((".github/workflows/" + . + ".yml") as $path |
            ({id: 1, path: $path, conclusion: "failure"}, {id: 2, path: $path, conclusion: (if $outcome == "pending" then null else $outcome end)})) end)} |
        .total_count = (.workflow_runs | length) + (if env.MOCK_FAIL == "runs-overflow" then 1 else 0 end)'
    ;;
*) exit 3 ;;
esac
MOCK
chmod +x "$work/gh"
export PATH="$work:$PATH"
check() {
    : >"$GITHUB_OUTPUT"
    : >"$CALLS"
    bash "$root/scripts/release/queue.sh"
    diff -u <(printf 'dmg=%s\nstore=%s\ntap=%s\n' "$1" "$2" "$3") "$GITHUB_OUTPUT"
    [[ $(wc -l <"$CALLS") -eq $4 ]] || {
        echo "queue made $(wc -l <"$CALLS") API calls instead of $4" >&2
        exit 1
    }
}
export MOCK_STATUSES='{}' MOCK_OUTCOMES='{}'
git switch -q --detach "$first^"
check "" "" "" 0
git switch -q --detach "$first"
check "$first" "$first" "" 2
git switch -q main
check "$fourth" "$fourth" "" 5
MOCK_STATUSES=$(by_commit "$second=success:release/dmg")
check "$fourth" "$fourth" "$second" 5
MOCK_STATUSES=$(by_commit "$third=success:release/dmg" "$third=success:release/store" "$third=success:release/tap")
check "$fourth" "$fourth" "" 3
MOCK_STATUSES=$(by_commit "$fourth=success:release/dmg" "$fourth=success:release/store" "$fourth=success:release/tap")
check "" "" "" 1
MOCK_STATUSES=$(by_commit "$fourth=success:release/dmg" "$third=success:release/tap")
check "" "$fourth" "$fourth" 2
MOCK_STATUSES='{}'
MOCK_OUTCOMES=$(by_commit "$fourth=pending")
check "$third" "$third" "" 6
MOCK_OUTCOMES=$(by_commit "$fourth=failure" "$third=absent")
check "$second" "$second" "" 7
MOCK_OUTCOMES='{}'
MOCK_STATUSES=$(by_commit "$fourth=failure:release/store" "$second=success:release/dmg")
check "$fourth" "" "$second" 5
MOCK_OUTCOMES=$(by_commit "$fourth=pending")
MOCK_STATUSES=$(by_commit "$third=failure:release/store" "$fourth=success:release/dmg" "$second=success:release/dmg")
check "" "" "" 3
MOCK_OUTCOMES=$(by_commit "$fourth=pending")
MOCK_STATUSES=$(by_commit "$fourth=failure:release/dmg" "$third=success:release/dmg" "$first=success:release/tap")
check "" "$third" "$third" 4
MOCK_STATUSES=$(by_commit "$fourth=failure:release/dmg" "$fourth=failure:release/store" "$fourth=failure:release/tap")
check "" "" "" 1
MOCK_STATUSES='{}'
MOCK_OUTCOMES=$(by_commit "$fourth=failure" "$third=failure" "$second=failure" "$first=pending")
check "" "" "" 8
MOCK_OUTCOMES='{}'
MOCK_STATUSES=$(by_commit "$fourth=error:release/dmg" "$fourth=pending:release/store" "$fourth=error:release/tap")
check "" "" "" 1
MOCK_STATUSES=$(by_commit "$fourth=pending:release/dmg")
check "" "$fourth" "" 5
MOCK_STATUSES=$(by_commit "$fourth=success:release/dmg")
MOCK_OUTCOMES=$(by_commit "$fourth=failure")
check "" "$third" "" 4
MOCK_OUTCOMES=$(by_commit "$fourth=absent")
check "" "$third" "" 4
MOCK_STATUSES='{}'
MOCK_OUTCOMES='{}'
for failure in status status-body status-overflow runs runs-body runs-overflow; do
    : >"$GITHUB_OUTPUT"
    if MOCK_FAIL=$failure bash "$root/scripts/release/queue.sh" 2>"$work/error"; then
        echo "Accepted a failing $failure request" >&2
        exit 1
    fi
    [ ! -s "$GITHUB_OUTPUT" ]
    case $failure in
    status-overflow) grep -q "$fourth has more statuses than one page" "$work/error" ;;
    runs-overflow)
        grep -q 'more workflow runs than one page' "$work/error"
        grep -q "cannot read the workflow runs of $fourth" "$work/error"
        ;;
    esac
done
checks() {
    local state
    state=$(jq -nc '{workflow_runs: [$ARGS.positional[] | capture("^(?<workflow>[a-z-]+)#(?<id>[0-9]+)=(?<conclusion>[a-z_]*)$") |
        {id: (.id | tonumber), path: (".github/workflows/" + .workflow + ".yml"), conclusion: (if .conclusion == "" then null else .conclusion end)}]} |
        .total_count = (.workflow_runs | length)' --args "${@:2}" | jq -r -f "$root/scripts/release/checks.jq")
    [ "$state" = "$1" ] || {
        echo "checks.jq: $state instead of $1 for ${*:2}" >&2
        exit 1
    }
}
checks absent
checks absent release#4=success
checks ready ci#1=success zizmor#2=success actions-lock#3=success release#4=failure
checks failed ci#1=failure zizmor#2=success actions-lock#3=success
checks failed ci#1=success zizmor#2=failure actions-lock#3=success
checks failed ci#1=success zizmor#2=success actions-lock#3=cancelled
checks failed ci#1=skipped zizmor#2=success actions-lock#3=success
checks pending ci#1= zizmor#2=success actions-lock#3=success
checks pending ci#1=success zizmor#2= actions-lock#3=success
checks pending ci#1=success zizmor#2=success actions-lock#3=
checks pending ci#1=success actions-lock#3=success
checks pending zizmor#2=success actions-lock#3=success
checks pending ci#1=success zizmor#2=success
checks failed ci#1=failure zizmor#2= actions-lock#3=success
checks failed zizmor#2=failure actions-lock#3=success
checks ready ci#5=success ci#1=failure zizmor#2=success actions-lock#3=success
checks failed ci#1=success ci#5=failure zizmor#2=success actions-lock#3=success
checks pending ci#9= ci#1=success zizmor#2=success actions-lock#3=success
checks ready zizmor#7=success zizmor#2=failure ci#1=success actions-lock#3=success
for runs in '{"total_count": 1, "workflow_runs": []}' '{"workflow_runs": []}'; do
    if jq -c . <<<"$runs" | jq -r -f "$root/scripts/release/checks.jq" 2>"$work/error"; then
        echo "checks.jq accepted $runs" >&2
        exit 1
    fi
done
mkdir -p tools "$work/assets"
printf '#!/bin/sh\necho 0.20261123.1\n' >tools/gitcalver.sh
chmod +x tools/gitcalver.sh
export MOCK_ASSETS="$work/assets" MOCK_SHA="$fourth"
cat >"$work/gh" <<'MOCK'
#!/bin/bash
set -eu
case "$1 $2" in
"api --paginate") cat "$MOCK_ASSETS/list.json" ;;
"release download")
    while (($#)); do
        case $1 in
        --pattern) file=$2; shift ;;
        --dir) directory=$2; shift ;;
        esac
        shift
    done
    cp "$MOCK_ASSETS/$file" "$directory/"
    ;;
"api repos/example/test/commits/v0.20261123.1") echo "$MOCK_SHA" ;;
*) echo "Unexpected GitHub mutation or query: $1 $2" >&2; exit 3 ;;
esac
MOCK
printf '%s\n' '[]' >"$MOCK_ASSETS/list.json"
: >"$GITHUB_OUTPUT"
bash "$root/scripts/release/github.sh" inspect
grep -qx published=false "$GITHUB_OUTPUT"
(
    cd "$MOCK_ASSETS"
    echo image >TypefaceOff-0.20261123.1.dmg
    echo inventory >TypefaceOff.spdx.json
    jq -n --arg revision "$MOCK_SHA" '{version:"0.20261123.1",revision:$revision}' >release.json
    shasum -a 256 TypefaceOff-0.20261123.1.dmg TypefaceOff.spdx.json >SHA256SUMS
    shasum -a 256 TypefaceOff-0.20261123.1.dmg TypefaceOff.spdx.json release.json SHA256SUMS |
        jq -Rs 'split("\n") | map(select(length>0) | split("  ") | {name:.[1],digest:("sha256:"+.[0]),state:"uploaded"}) | [[{tag_name:"v0.20261123.1", assets:., immutable:true, draft:false, prerelease:false}]]' >list.json
)
: >"$GITHUB_OUTPUT"
bash "$root/scripts/release/github.sh" inspect
grep -qx published=true "$GITHUB_OUTPUT"
bash "$root/scripts/release/github.sh" publish
if MOCK_SHA="$first" bash "$root/scripts/release/github.sh" inspect 2>"$work/error"; then
    echo "Accepted a release tagged at another commit" >&2
    exit 1
fi
grep -q 'does not point at' "$work/error"
echo '{}' >"$MOCK_ASSETS/release.json"
if bash "$root/scripts/release/github.sh" publish 2>"$work/error"; then
    echo "Accepted a mismatched release" >&2
    exit 1
fi
grep -q 'does not name' "$work/error"
export MOCK_STATE="$work/release-state"
cat >"$work/gh" <<'MOCK'
#!/bin/bash
set -eu
echo "$*" >>"$MOCK_STATE/calls"
created=false
if [ -e "$MOCK_STATE/created" ]; then created=true; fi
published=false
draft=true
if [ -e "$MOCK_STATE/published" ]; then
    published=true
    draft=false
fi
assets() {
    local file
    for file in "$MOCK_STATE"/files/*; do
        [ -e "$file" ] || continue
        jq -n --arg name "${file##*/}" --arg digest "sha256:$(shasum -a 256 "$file" | cut -d ' ' -f 1)" '{name: $name, digest: $digest, state: "uploaded"}'
    done | jq -s .
}
case "$1 $2" in
"api --paginate")
    jq -n --argjson created "$created" --argjson draft "$draft" --argjson immutable "${MOCK_IMMUTABLE:-$published}" --argjson other "$MOCK_OTHER" --arg sha "$MOCK_SHA" --argjson assets "$(assets)" \
        '[[(if $created then [{tag_name: "v0.20261123.1", draft: $draft, prerelease: false, immutable: $immutable, target_commitish: $sha, assets: $assets}] else [] end) + $other]]'
    ;;
"api repos/example/test/git/matching-refs/tags/v0.20261123.1")
    if [ "$published" = true ]; then echo '[{"ref": "refs/tags/v0.20261123.1"}]'; else echo '[]'; fi
    ;;
"api repos/example/test/commits/v0.20261123.1") echo "$MOCK_SHA" ;;
"release create") touch "$MOCK_STATE/created" ;;
"release upload")
    shift 3
    while (($#)); do
        case $1 in
        --repo) shift ;;
        --clobber) ;;
        *) cp "$1" "$MOCK_STATE/files/" ;;
        esac
        shift
    done
    ;;
"release view")
    jq -n --argjson draft "$draft" --argjson assets "$(assets)" '{isDraft: $draft, assets: $assets}'
    ;;
"release edit") touch "$MOCK_STATE/published" ;;
"release download")
    while (($#)); do
        case $1 in
        --pattern) file=$2; shift ;;
        --dir) directory=$2; shift ;;
        esac
        shift
    done
    cp "$MOCK_STATE/files/$file" "$directory/"
    ;;
*) echo "Unexpected GitHub mutation or query: $1 $2" >&2; exit 3 ;;
esac
MOCK
mkdir -p .build/developer-id/assets
(
    cd .build/developer-id/assets
    echo image >TypefaceOff-0.20261123.1.dmg
    echo inventory >TypefaceOff.spdx.json
    shasum -a 256 TypefaceOff-0.20261123.1.dmg TypefaceOff.spdx.json >SHA256SUMS
)
publish() {
    rm -rf "$MOCK_STATE"
    mkdir -p "$MOCK_STATE/files"
    : >"$GITHUB_OUTPUT"
    bash "$root/scripts/release/github.sh" publish
}
export MOCK_OTHER='[]'
publish
grep -Eq "^release create v0.20261123.1 --repo example/test --draft --target $fourth " "$MOCK_STATE/calls"
grep -qx 'release edit v0.20261123.1 --repo example/test --draft=false --latest=true' "$MOCK_STATE/calls"
: >"$GITHUB_OUTPUT"
bash "$root/scripts/release/github.sh" inspect
grep -qx published=true "$GITHUB_OUTPUT"
export MOCK_OTHER='[{"tag_name": "v0.20261124.1", "draft": false, "prerelease": false}]'
publish
grep -qx 'release edit v0.20261123.1 --repo example/test --draft=false --latest=false' "$MOCK_STATE/calls"
export MOCK_OTHER='[]' MOCK_IMMUTABLE=false
if publish 2>"$work/error"; then
    echo "Accepted a mutable release" >&2
    exit 1
fi
grep -q 'enable immutable releases' "$work/error"
unset MOCK_IMMUTABLE
cat >"$work/swiftc" <<'MOCK'
#!/bin/bash
set -eu
echo "$*" >>"$MOCK_SWIFTC_CALLS"
while (($#)); do
    if [ "$1" = -o ]; then cp "$MOCK_STATE_TOOL" "$2"; fi
    shift
done
MOCK
cat >"$work/state" <<'MOCK'
#!/bin/bash
set -eu
head -1 "$MOCK_STATES"
sed -i.bak '1d' "$MOCK_STATES"
MOCK
cat >"$work/make" <<'MOCK'
#!/bin/bash
set -eu
[ "$1" = testflight ] || exit 1
echo upload >>"$MOCK_UPLOADS"
MOCK
chmod +x "$work/"{swiftc,state,make}
export MOCK_STATE_TOOL="$work/state" MOCK_STATES="$work/states" MOCK_UPLOADS="$work/uploads" MOCK_SWIFTC_CALLS="$work/swiftc-calls"
export STORE_PROFILE_UUID=test ASC_KEY_PATH=/dev/null ASC_KEY_ID=test ASC_ISSUER_ID=test ASC_APP_ID=1
for existing in VALID PROCESSING ABSENT; do
    printf '%s\n' "$existing" VALID >"$MOCK_STATES"
    : >"$MOCK_UPLOADS"
    bash "$root/scripts/release/store.sh"
    if [ "$existing" = ABSENT ]; then grep -qx upload "$MOCK_UPLOADS"; else [ ! -s "$MOCK_UPLOADS" ]; fi
done
grep -q -- '-swift-version 6 -warnings-as-errors' "$MOCK_SWIFTC_CALLS"
for existing in INVALID FAILED; do
    printf '%s\n' "$existing" >"$MOCK_STATES"
    : >"$MOCK_UPLOADS"
    : >"$GITHUB_OUTPUT"
    if bash "$root/scripts/release/store.sh" 2>"$work/error"; then exit 1; fi
    grep -qx rejected=true "$GITHUB_OUTPUT"
    [ ! -s "$MOCK_UPLOADS" ]
done
printf '%s\n' ABSENT INVALID >"$MOCK_STATES"
: >"$MOCK_UPLOADS"
: >"$GITHUB_OUTPUT"
if bash "$root/scripts/release/store.sh" 2>"$work/error"; then exit 1; fi
grep -qx rejected=true "$GITHUB_OUTPUT"
grep -qx upload "$MOCK_UPLOADS"
shims="$work/shims"
mkdir -p "$shims"
cat >"$shims/hdiutil" <<'MOCK'
#!/bin/bash
set -eu
case "$1" in
create)
    previous=
    for argument in "$@"; do
        if [ "$previous" = -srcfolder ]; then printf '%s' "$argument" >"$DMG_STATE/source"; fi
        previous=$argument
    done
    echo image >"${!#}"
    ;;
attach)
    previous=
    for argument in "$@"; do
        if [ "$previous" = -mountpoint ]; then mountpoint=$argument; fi
        previous=$argument
    done
    mkdir -p "$mountpoint"
    cp -R "$(cat "$DMG_STATE/source")/." "$mountpoint/"
    if [ -n "${DMG_BAD_LINK:-}" ]; then
        rm "$mountpoint/Applications"
        ln -s /nonexistent "$mountpoint/Applications"
    fi
    ;;
detach) ;;
*) exit 9 ;;
esac
MOCK
cat >"$shims/xcrun" <<'MOCK'
#!/bin/bash
set -eu
case "$1 $2" in
"notarytool submit") echo '{"id": "test", "status": "Accepted", "message": "Processing complete"}' ;;
"stapler staple")
    remaining=$(cat "$DMG_STATE/staple-failures")
    if [ "$remaining" -gt 0 ]; then
        echo $((remaining - 1)) >"$DMG_STATE/staple-failures"
        exit 65
    fi
    ;;
"stapler validate") ;;
*) exit 9 ;;
esac
MOCK
cat >"$shims/ditto" <<'MOCK'
#!/bin/bash
cp -R "$1" "$2"
MOCK
for tool in codesign lipo sleep spctl; do printf '#!/bin/bash\nexit 0\n' >"$shims/$tool"; done
chmod +x "$shims/"*
export DMG_STATE="$work/dmg-state"
archive() {
    local info="$work/archive/Products/Applications/TypefaceOff.app/Contents/Info.plist"
    rm -rf "$work/archive"
    mkdir -p "${info%/*}/MacOS"
    echo binary >"${info%/*}/MacOS/TypefaceOff"
    plutil -create xml1 "$info"
    plutil -insert CFBundleIdentifier -string "$1" "$info"
    plutil -insert CFBundleShortVersionString -string 0.20261123.1 "$info"
    plutil -insert CFBundleVersion -string "$2" "$info"
    plutil -insert TypefaceOffDisplayVersion -string "$3" "$info"
    echo '{}' >"$work/archive/TypefaceOff.spdx.json"
}
# macOS runners run the system bash, whose errexit ignores a failing `[[ ]]`.
dmg() {
    rm -rf "$work/out" "$DMG_STATE"
    mkdir -p "$DMG_STATE"
    echo "${DMG_STAPLE_FAILURES:-0}" >"$DMG_STATE/staple-failures"
    PATH="$shims:$PATH" ASC_KEY_PATH=/dev/null ASC_KEY_ID=test ASC_ISSUER_ID=test /bin/bash "$root/scripts/release/dmg.sh" "$work/archive" "$work/out"
}
rejects() {
    if dmg 2>"$work/error"; then
        echo "Accepted: $1" >&2
        exit 1
    fi
    grep -q -- "$1" "$work/error"
    [ ! -e "$work/out/TypefaceOff-0.20261123.1.dmg" ]
}
archive com.typefaceoff 20261123.1 0.20261123.1
dmg
diff -u <(printf 'SHA256SUMS\nTypefaceOff-0.20261123.1.dmg\nTypefaceOff.spdx.json\n') <(LC_ALL=C ls "$work/out")
DMG_STAPLE_FAILURES=4 dmg
DMG_STAPLE_FAILURES=5 rejects 'stapling failed'
archive com.example.wrong 20261123.1 0.20261123.1
rejects 'bundle identifier'
archive com.typefaceoff 1 0.20261123.1
rejects 'build number'
archive com.typefaceoff 20261123.1 0.20261123.1-dirty.0123456
rejects 'displayed version'
archive com.typefaceoff 20261123.1 0.20261123.1
DMG_BAD_LINK=1 rejects 'Applications link'
cd "$work/repo"
mkdir -p packaging/homebrew
cp "$root/packaging/homebrew/typefaceoff.rb.in" packaging/homebrew/
export TAP_REMOTE="$work/tap.git" TAP_STATE="$work/tap-state" GITHUB_OUTPUT="$work/output"
export MOCK_SHA GIT_CONFIG_GLOBAL="$work/gitconfig" TAP_DIGEST=0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef
MOCK_SHA=$(git rev-parse HEAD)
git config -f "$GIT_CONFIG_GLOBAL" "url.file://$TAP_REMOTE.insteadOf" https://github.com/shields/homebrew-tap.git
cat >"$work/gh" <<'MOCK'
#!/bin/bash
set -euo pipefail
echo "$*" >>"$TAP_STATE/calls"
filter=.
fields=""
head=""
args=("$@")
for ((i = 0; i < $#; i++)); do
    case ${args[i]} in
    --jq) filter=${args[i + 1]} ;;
    --json) fields=${args[i + 1]} ;;
    --head) head=${args[i + 1]} ;;
    esac
done
prs="$TAP_STATE/prs.json"
update() { jq "$@" "$prs" >"$prs.new" && mv "$prs.new" "$prs"; }
case "$1 $2" in
"release view")
    jq -n --arg digest "sha256:$TAP_DIGEST" '{isImmutable: true, isDraft: false, assets: [{name: "TypefaceOff-0.20261123.1.dmg", digest: $digest}]}'
    ;;
"api repos/shields/typefaceoff/commits/v0.20261123.1") echo "$MOCK_SHA" ;;
"pr list")
    [[ $filter == . || -n $fields ]] || exit 3
    jq --arg head "$head" --arg fields "$fields" 'map(select(.state == "OPEN" and ($head == "" or .headRefName == $head)) | del(.state, .autoMerge) | with_entries(select(.key | IN($fields | split(",")[]))))' "$prs" | jq -r "$filter"
    ;;
"pr create")
    number=$(($(jq length "$prs") + 1))
    update --argjson number "$number" --arg head "$head" '. + [{number: $number, headRefName: $head, isCrossRepository: false, mergeable: "MERGEABLE", state: "OPEN", autoMerge: false}]'
    echo "https://github.com/shields/homebrew-tap/pull/$number"
    ;;
"pr view")
    jq --argjson number "${3##*/}" '.[] | select(.number == $number) | {autoMergeRequest: (if .autoMerge then {} else null end)}' "$prs" | jq -r "$filter"
    ;;
"pr merge") update --argjson number "${3##*/}" 'map(if .number == $number then .autoMerge = true else . end)' ;;
"pr close")
    branch=$(jq -r --argjson number "$3" '.[] | select(.number == $number and .state == "OPEN") | .headRefName' "$prs")
    [[ -n $branch && " $* " == *" --delete-branch "* ]] || exit 3
    git --git-dir="$TAP_REMOTE" update-ref -d "refs/heads/$branch"
    update --argjson number "$3" 'map(if .number == $number then .state = "CLOSED" else . end)'
    ;;
*)
    echo "Unexpected GitHub call: $*" >&2
    exit 3
    ;;
esac
MOCK
tap_branch() {
    git -C "$work/tap-seed" switch -q -C "$1" main
    printf '%s\n' "$2" >"$work/tap-seed/Casks/typefaceoff.rb"
    git -C "$work/tap-seed" commit -qam "$1"
    git -C "$work/tap-seed" push -q origin "$1"
}
tap_setup() {
    rm -rf "$TAP_REMOTE" "$work/tap-seed" "$TAP_STATE"
    mkdir -p "$TAP_STATE"
    echo "$1" >"$TAP_STATE/prs.json"
    git init -q --bare -b main "$TAP_REMOTE"
    git init -q -b main "$work/tap-seed"
    git -C "$work/tap-seed" config user.name test
    git -C "$work/tap-seed" config user.email test@example.invalid
    mkdir "$work/tap-seed/Casks"
    sed -e 's/@VERSION@/0.20261122.1/' -e "s/@SHA256@/$TAP_DIGEST/" packaging/homebrew/typefaceoff.rb.in >"$work/tap-seed/Casks/typefaceoff.rb"
    git -C "$work/tap-seed" add Casks
    git -C "$work/tap-seed" commit -qm seed
    git -C "$work/tap-seed" remote add origin "$TAP_REMOTE"
    git -C "$work/tap-seed" push -q origin main
}
tap() {
    : >"$GITHUB_OUTPUT"
    SOURCE_TOKEN=source-token bash "$root/scripts/release/tap.sh"
}
proposal='release/typefaceoff-0.20261123.1'
open_prs() { jq -r 'map(select(.state == "OPEN") | "\(.number) \(.headRefName) \(.autoMerge)") | .[]' "$TAP_STATE/prs.json"; }
expected_open() {
    printf '%s\n' '2 release/typefaceoff-0.20261122.3 false' '3 release/typefaceoff-0.20261124.1 true' '4 release/typefaceoff-0.1-manual false' '6 release/typefaceoff-0.20261122.2-hotfix false' "7 $proposal true"
}
set_mergeable() {
    jq --argjson number "$1" --arg state "$2" 'map(if .number == $number then .mergeable = $state else . end)' "$TAP_STATE/prs.json" >"$TAP_STATE/prs.new"
    mv "$TAP_STATE/prs.new" "$TAP_STATE/prs.json"
}
tap_setup "$(jq -nc '[
    {number: 1, headRefName: "release/typefaceoff-0.20261122.2", isCrossRepository: false, mergeable: "MERGEABLE", state: "OPEN", autoMerge: true},
    {number: 2, headRefName: "release/typefaceoff-0.20261122.3", isCrossRepository: true, mergeable: "MERGEABLE", state: "OPEN", autoMerge: false},
    {number: 3, headRefName: "release/typefaceoff-0.20261124.1", isCrossRepository: false, mergeable: "MERGEABLE", state: "OPEN", autoMerge: true},
    {number: 4, headRefName: "release/typefaceoff-0.1-manual", isCrossRepository: false, mergeable: "MERGEABLE", state: "OPEN", autoMerge: false},
    {number: 5, headRefName: "release/typefaceoff-0.20261121.1", isCrossRepository: false, mergeable: "CONFLICTING", state: "OPEN", autoMerge: true},
    {number: 6, headRefName: "release/typefaceoff-0.20261122.2-hotfix", isCrossRepository: false, mergeable: "MERGEABLE", state: "OPEN", autoMerge: false}]')"
tap_branch release/typefaceoff-0.20261122.2 superseded
tap_branch release/typefaceoff-0.20261121.1 superseded
tap
diff -u <(expected_open) <(open_prs)
for superseded in release/typefaceoff-0.20261121.1 release/typefaceoff-0.20261122.2; do
    [ -z "$(git --git-dir="$TAP_REMOTE" branch --list "$superseded")" ]
done
main_tip=$(git --git-dir="$TAP_REMOTE" rev-parse main)
[ "$(git --git-dir="$TAP_REMOTE" rev-parse "$proposal^")" = "$main_tip" ]
proposed=$(git --git-dir="$TAP_REMOTE" rev-parse "$proposal")
grep -qx "pr merge https://github.com/shields/homebrew-tap/pull/7 -R shields/homebrew-tap --auto --squash --match-head-commit $proposed" "$TAP_STATE/calls"
[ ! -s "$GITHUB_OUTPUT" ]
# Each rerun gets a new commit time, so a rerun that rebuilds the branch fails its push.
for mergeable in MERGEABLE UNKNOWN; do
    set_mergeable 7 "$mergeable"
    tick
    tap
    diff -u <(expected_open) <(open_prs)
    [ "$(git --git-dir="$TAP_REMOTE" rev-parse "$proposal")" = "$proposed" ]
done
[ "$(grep -c '^pr merge ' "$TAP_STATE/calls")" = 1 ]
tap_setup "$(jq -nc --arg head "$proposal" '[{number: 1, headRefName: $head, isCrossRepository: false, mergeable: "CONFLICTING", state: "OPEN", autoMerge: true}]')"
tap_branch "$proposal" "$(sed -e 's/@VERSION@/0.20261123.1/' -e "s/@SHA256@/$TAP_DIGEST/" packaging/homebrew/typefaceoff.rb.in)"
tap_branch other unrelated
git -C "$work/tap-seed" switch -q main
sed -e 's/@VERSION@/0.20261122.2/' -e "s/@SHA256@/$TAP_DIGEST/" packaging/homebrew/typefaceoff.rb.in >"$work/tap-seed/Casks/typefaceoff.rb"
git -C "$work/tap-seed" commit -qam 'Merged older update'
git -C "$work/tap-seed" push -q origin main
tap
diff -u <(printf '2 %s true\n' "$proposal") <(open_prs)
main_tip=$(git --git-dir="$TAP_REMOTE" rev-parse main)
[ "$(git --git-dir="$TAP_REMOTE" rev-parse "$proposal^")" = "$main_tip" ]
git --git-dir="$TAP_REMOTE" show "$proposal:Casks/typefaceoff.rb" | grep -qx '  version "0.20261123.1"'
git --git-dir="$TAP_REMOTE" show-ref --verify --quiet refs/heads/other
grep -q '^pr close 1 -R shields/homebrew-tap --delete-branch ' "$TAP_STATE/calls"
tap_setup '[]'
git -C "$work/tap-seed" switch -q main
sed -e 's/@VERSION@/0.20261123.1/' -e "s/@SHA256@/$TAP_DIGEST/" packaging/homebrew/typefaceoff.rb.in >"$work/tap-seed/Casks/typefaceoff.rb"
git -C "$work/tap-seed" commit -qam 'Merged update'
git -C "$work/tap-seed" push -q origin main
tap
grep -qx merged=true "$GITHUB_OUTPUT"
[ "$(grep -c '^pr ' "$TAP_STATE/calls")" = 0 ]
