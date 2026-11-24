#!/bin/bash
set -euo pipefail
gh api --method POST "repos/$GITHUB_REPOSITORY/statuses/$(git rev-parse HEAD)" \
    -f "state=${2:-success}" -f "context=release/$1" -f "target_url=$GITHUB_SERVER_URL/$GITHUB_REPOSITORY/actions/runs/$GITHUB_RUN_ID" >/dev/null
