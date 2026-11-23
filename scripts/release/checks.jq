.workflow_runs as $runs |
["ci", "zizmor", "actions-lock"] | map(
    . as $workflow | [$runs[] | select(.path == (".github/workflows/" + $workflow + ".yml"))]
    | max_by(.id) | if . == null then "missing" else (.conclusion // "pending") end
) |
if all(. == "missing") then "absent"
elif any(. != "success" and . != "pending" and . != "missing") then "failed"
elif all(. == "success") then "ready"
else "pending" end
