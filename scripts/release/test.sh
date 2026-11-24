#!/bin/bash
set -euo pipefail
root=$(pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
git init -q -b main "$work/repo"
cd "$work/repo"
git config user.name test
git config user.email test@example.invalid
git commit -q --allow-empty -m 'Before releases'
git switch -qc distribution
mkdir -p scripts/release .github/workflows
touch .github/workflows/release.yml
cp "$root/scripts/release/checks.jq" scripts/release/
git add scripts .github
git commit -qm 'Add release workflow'
git switch -q main
git merge -q --no-ff distribution -m first
for commit in second third; do
    git commit -q --allow-empty -m "$commit"
done
export GITHUB_REPOSITORY=example/test RUNNER_TEMP="$work" GITHUB_OUTPUT="$work/output"
first=$(git rev-parse HEAD~2)
second=$(git rev-parse HEAD~1)
third=$(git rev-parse HEAD)
export first
cat >"$work/gh" <<'MOCK'
#!/bin/bash
set -eu
case $2 in
*/status)
    sha=${2%/status}
    if [[ ${sha##*/} == "$first" ]]; then
        printf '%s\n' "$completed"
    else
        echo '[]'
    fi
    ;;
*/runs\?*)
    outcome=success
    if [[ $2 == *"$first"* ]]; then outcome=$first_outcome; fi
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
git switch -q --detach "$first^"
check "" "" ""
git switch -q --detach "$first"
check "$first" "$first" ""
git switch -q main
check "$first" "$first" ""
completed='["store-rejected"]'
check "$first" "$second" ""
completed='["release/dmg"]'
check "$second" "$first" "$first"
completed='["release/dmg","release/store","release/tap"]'
check "$second" "$second" ""
completed='[]'
first_outcome=pending
check "" "" ""
first_outcome=failure
check "$second" "$second" ""
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
