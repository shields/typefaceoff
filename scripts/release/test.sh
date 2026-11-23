#!/bin/bash
set -euo pipefail
root=$(pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
git init -q -b main "$work/repo"
cd "$work/repo"
mkdir -p scripts/release
cp "$root/scripts/release/checks.jq" scripts/release/
git add scripts
for commit in first second third; do
    git -c user.name=test -c user.email=test@example.invalid commit -q --allow-empty -m "$commit"
done
export GITHUB_REPOSITORY=example/test RUNNER_TEMP="$work" GITHUB_OUTPUT="$work/output"
RELEASE_START_SHA=$(git rev-parse HEAD~2)
second=$(git rev-parse HEAD~1)
third=$(git rev-parse HEAD)
export RELEASE_START_SHA
cat >"$work/gh" <<'MOCK'
#!/bin/bash
set -eu
case $2 in
*/status)
    sha=${2%/status}
    if [[ ${sha##*/} == "$RELEASE_START_SHA" ]]; then
        printf '%s\n' "$completed"
    else
        echo '[]'
    fi
    ;;
*/runs\?*)
    outcome=success
    if [[ $2 == *"$RELEASE_START_SHA"* ]]; then outcome=$first_outcome; fi
    jq -n --arg outcome "$outcome" '{workflow_runs: ["ci","actions-lock","zizmor"] | map({id: 1, path: (".github/workflows/" + . + ".yml"), conclusion: (if $outcome == "pending" then null else $outcome end)})}'
    ;;
*) exit 3 ;;
esac
MOCK
chmod +x "$work/gh"
export PATH="$work:$PATH"
check() {
    : >"$GITHUB_OUTPUT"
    bash "$root/scripts/release/queue.sh"
    diff -u <(printf 'dmg=%s\nstore=%s\ntap=%s\n' "$1" "$2" "$3") "$GITHUB_OUTPUT"
}
export completed='[]' first_outcome=success
check "$RELEASE_START_SHA" "$RELEASE_START_SHA" ""
completed='["store-rejected"]'
check "$RELEASE_START_SHA" "$second" ""
completed='["release/dmg"]'
check "$second" "$RELEASE_START_SHA" "$RELEASE_START_SHA"
completed='["release/dmg","release/store","release/tap"]'
check "$second" "$second" ""
completed='[]'
first_outcome=pending
check "" "" ""
first_outcome=failure
check "$second" "$second" ""
RELEASE_START_SHA=$third
first_outcome=success
check "$third" "$third" ""
mkdir -p tools "$work/assets"
printf '#!/bin/sh\necho 0.20261123.1\n' >tools/gitcalver.sh
chmod +x tools/gitcalver.sh
export MOCK_ASSETS="$work/assets" MOCK_SHA="$third"
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
bash "$root/scripts/release/github.sh" publish
echo '{}' >"$MOCK_ASSETS/release.json"
if bash "$root/scripts/release/github.sh" publish; then
    echo "Accepted a mismatched release" >&2
    exit 1
fi
cat >"$work/swiftc" <<'MOCK'
#!/bin/bash
set -eu
cp "$MOCK_STATE_TOOL" "$3"
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
[[ $1 == testflight ]]
echo upload >>"$MOCK_UPLOADS"
MOCK
chmod +x "$work/"{swiftc,state,make}
export MOCK_STATE_TOOL="$work/state" MOCK_STATES="$work/states" MOCK_UPLOADS="$work/uploads"
export STORE_PROFILE_UUID=test ASC_KEY_PATH=/dev/null ASC_KEY_ID=test ASC_ISSUER_ID=test ASC_APP_ID=1
for existing in VALID PROCESSING ABSENT; do
    printf '%s\n' "$existing" VALID >"$MOCK_STATES"
    : >"$MOCK_UPLOADS"
    bash "$root/scripts/release/store.sh"
    if [[ $existing == ABSENT ]]; then grep -qx upload "$MOCK_UPLOADS"; else [[ ! -s $MOCK_UPLOADS ]]; fi
done
printf '%s\n' ABSENT INVALID >"$MOCK_STATES"
if bash "$root/scripts/release/store.sh" 2>"$work/rejection"; then exit 1; fi
grep -qx rejected=true "$GITHUB_OUTPUT"
