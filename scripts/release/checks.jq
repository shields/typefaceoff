(.total_count // error("workflow runs response lacks total_count")) as $total |
if $total > (.workflow_runs | length) then error("more workflow runs than one page") else . end |
.workflow_runs as $runs |
["ci", "zizmor", "actions-lock"] | map(
    . as $workflow | [$runs[] | select(.path == (".github/workflows/" + $workflow + ".yml"))]
    | max_by(.id) | if . == null then "missing" else (.conclusion // "pending") end
) |
if all(. == "missing") then "absent"
elif any(. != "success" and . != "pending" and . != "missing") then "failed"
elif all(. == "success") then "ready"
else "pending" end
