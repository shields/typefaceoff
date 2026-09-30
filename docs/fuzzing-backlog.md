# UI fuzzer review backlog

Follow-ups from a review of two campaigns on 2026-09-28. Each item names the
evidence and the first step so it can be picked up without redoing the analysis.
Item ids in parentheses (A1, VT4, ...) refer to the candidate lists from the
review; the raw outputs were saved untracked under `.build/fuzz-review/`.

## The campaigns

- Host campaign, `.build/ui-fuzz`: 19 executions in 5 minutes on 2026-09-27
  (about commit `db9ee32`). Every execution became a finding: 13 `slow`, 6
  `automation`.
- VM campaign, `.build/ui-fuzz-vm`: 1,071 executions from 08:26 to 12:35 on
  2026-09-28 in the `typefaceoff-fuzz` guest. The app under test matches commit
  `91baf55`'s lineage, not the startup work merged later. The first 216 runs
  (08:26-09:59) predate the three-hour campaign.
- Result: no crash, hang, correctness, or unavailable findings. 593 executions
  (55.4%) aborted on a harness failure ("Control not found" 590, `AXPress`
  failure 3). The 20 `slow` findings are the cap of the top-20 leaderboard.
- Coverage: 3,373 of 3,711 regions (90.9%) were reached by execution 71. The
  other 1,000 executions added 338 regions, mostly in two bursts (executions 519
  and 673, which reached the Match sheet).

Four blind spots hid this, so "no crashes" says little: stale process liveness
(crash detection cannot fire), inert mouse events, a custom-text stress path
that never lands, and empty app stdout/stderr logs.

## Merged from another session (38a7647)

Control resolution, window scoping, idle waits, and app accessibility names (see
`.build/handoff/control-not-found.md`): a tested resolver, a skip ledger that
counts and surfaces skipped steps, an idle wait, resolution in the focused
window, and stable identifiers for inspector controls. It covers A1-A3, VT1-VT3,
and VB2. The combination with waves 1 to 3 passed the full gate but has not run
against a live UI; measure the abort rate and the skip ledger on the next smoke
test or campaign.

## Still owned by another session

- Mouse delivery (`.build/handoff/mouse-clicks.md`, D1, VC3).

## Merged to main (9b829d7)

Four branches, each committed through LGTMCP, integrated without conflicts, and
fast-forwarded into `main` after `make coverage` passed. Nothing here has run
against a live UI; the checks that need one are listed with each branch.

- `fuzzfix/mutation-state` (VT4, VC4, VB3; the Cmd-W and unchanged-base
  findings). The mutator tracks mode, sheet, popover, and appearance lock, and
  puts an idempotent enabler before controls that need a state. Offline on the
  VM corpus, plans with a state-blind action fell from 46% to 0%, and Cmd-W was
  replaced by Shift-Cmd-M. Confirm in a campaign that Escape closes sheets and
  popovers in time and that Cmd-1/Cmd-2/Cmd-F work right after it.
- `fuzzfix/process-liveness` (VR1, VR2). `kill(pid, 0)` replaces the stale
  `isTerminated`, so the two 2 s waits should shrink to about 0.1 s per run.
  Exit before the driver's own quit is now a `crash` finding
  (`unexpected-termination`, or `launch-termination` during launch) and no
  longer feeds the availability retry loop. New metadata: `quit-ms`,
  `quit-forced`. Confirm with `make fuzz FUZZ_ARGS='--duration 1m'` (takes over
  the screen): the gap between `durationMilliseconds` and workload plus
  discovery should fall from about 5.2 s to about 1.2 s, no clean run should
  report a crash, and killing the app mid-run should give `kind=crash`.
- `fuzzfix/corpus-hygiene` (VR6, VT6; the dead `CoverageBuckets.bucket`). A
  campaign now stops, naming the file, on a corpus, state, availability, or slow
  report it cannot load (tried against the real VM and host artifacts). The
  driver uses the tested bucket function. The corpus copy of an aborted run
  drops the action that never ran; the finding keeps the full trace.
- `fuzzfix/ranking-key` (VP3, VB7). Ranking depends on the fonts, both
  trackings, the B/A size ratio, and the text, not on absolute size, so a new
  `DifferenceInput` keys both the engine cache and the app's ranking key. Size
  edits that keep the ratio no longer clear scores or show "Comparing glyphs".
  Confirm in the running app that the strip stays populated on a linked size
  step. Tracking edits still restart ranking, so that half of the aborts
  remains.

Follow-ups the branches surfaced:

- Mutation: track whether font B exists (Match `Tracking`/`Weight` and Font B
  requirements) and inspector visibility; `Zoom in`/`Zoom out` are disabled at
  the zoom limits, so pressing them gives `AXPress -25200`, which is not
  modelled; corpus entry `00000256` still contains Cmd-W and 35 of 10,600
  mutated plans inherit it; revisit the "mode unknown after a canvas click or
  drag" rule once mouse delivery works; update the requirement table if
  accessibility names such as `Font A family` change. The acceptance scripts
  (`.build/analysis/model.py`, `acceptance.py`) are untracked and worth moving
  to `scripts/` if the check should be repeatable.
- Liveness: `require()` polls for up to 2 s after the app dies mid-action, so
  the resolver should check `ProcessLiveness.isAlive` in its polling loops;
  `forceTerminate` failing to remove the process is not reported; four exit-gap
  outliers (8-24 s) are unexplained; `waitForWorkbench` still waits up to 2 s
  for an app that died after showing a window.
- Left by the final review as decisions or unverified:
  - A build that dies at startup now yields a `launch-termination` crash finding
    per execution with no backoff (it used to back off 5-60 s through the
    availability path), repeating every 1-3 s until interrupted. Count
    consecutive launch terminations next to `CampaignBackoff` and abort after a
    few.
  - Crash detection samples `hasExited` once after a driver error. A crashed
    process still held by ReportCrash keeps `kill(pid, 0)` succeeding, so it
    would be recorded as an automation finding, and a pid that vanishes only
    during the quit adds no crash finding. Plausible; a real crash under the
    fuzzer would confirm it.
  - The mutation model does not track inspector visibility or whether font B
    exists (the `Font A family` enabler fails when the inspector is hidden;
    after Font B is set to None, Match, Swap, and Lock are disabled), and it
    assumes the Match sheet's `Apply` is always usable and `Weight` always
    exists (`Apply` is disabled until a fit improves; `Weight` needs a variable
    font B).
  - Overlays opened or closed by controls the model does not know (menu-bar
    items, the Sample pop-up, picker row buttons, the Edit menu's `Undo <name>`)
    leave sheet, popover, and lock state stale; wave 4 models `Cancel matching`
    and the sheet controls. Return is modelled as closing the editor sheet, but
    in the multi-line editor after `setValue` it may insert a newline.
- Slow quit (VR9): 83.8% of runs with 20 or more actions that end with a sheet
  open ignore the polite quit, against 5.3% with no sheet. Explained by a probe
  and handled in wave 4 (see "Merged to main: wave 4"); `quit-ms` and
  `quit-forced` keep supplying the data.
- Corpus: the 80 existing corpus entries with an unresolvable tail are not
  touched (trim on load or migrate); `loadTraceOrReport` still skips the schema
  version check; `fuzz-benchmark` with an empty or wrong `--corpus` now fails
  loudly instead of benchmarking 0 traces.
- Ranking: keep the "Comparing glyphs" indicator in the accessibility tree, or
  wait for it, for the edits that legitimately restart ranking (tracking, font,
  feature, text). The feature-preview half of VB7 rests on a false premise:
  previews depend on tracking through shaping. `DifferenceInputTests` takes
  about 10 s in debug. The engine now rounds the B/A ratio to 1e-9 (invisible,
  and bit-identical for ratio 1).

## Merged to main: wave 2

- `fuzzfix/launch-loop-guard`. Five consecutive executions that end in a
  `launch-termination` crash finding stop the campaign with an error naming the
  streak and the last finding file (fail-fast; the evidence is written first).
  Not covered, and still able to loop without progress: `launchFailed` (an
  `openApplication` error, the likeliest real form of a bad signature),
  `launchTimedOut`, and `startup-telemetry` are automation findings with
  free-form signatures. Give the runner stable signatures for them and count
  them in the same streak, after the runner rewrite lands. Separately,
  `preserveFindings` writes one file per finding per execution with no
  de-duplication, so a campaign that hits the same crash repeatedly grows
  `findings/crash` and `runs/` without bound.
- `fuzzfix/output-capture`. In fuzz builds the app appends stdout and stderr to
  the run directory's `stdout.log` and `stderr.log` (`dup2`, stdout
  line-buffered, stderr unbuffered so a trap still leaves its message). After an
  unexpected exit the driver waits up to 10 s for the ReportCrash `.ips` file,
  matched by pid and process name (the file name has no pid), copies it into the
  run directory, and adds the exception type, signal, and termination reason to
  the crash finding. Checked against a real crash of a throwaway binary (the
  report appeared about 1 s later). Not confirmed: that the live app's
  `procName` is `TypefaceOff` and that guest reports land in the same directory;
  that stdio is captured inside the LaunchServices-launched app; the 10 s wait
  for an app that exits without a report. `StandardStreamRedirect` is compiled
  in every configuration so it can be tested (about 15 lines in Release).
- `fuzzfix/glyph-navigation`. Next from a glyph that is not in the list now
  selects the first entry and Previous the last, as `CharacterSearchPicker.move`
  does (it used to start at index 0, so Next skipped the first entry). One test
  that pinned the old outcome
  (`glyphButtonsAndCharacterEntrySelectTheRequestedGlyph` expected U+0022 after
  a candidate list that starts at U+0021) was changed.

## Merged to main: wave 3

- `fuzzfix/stderr-finding`. Anything the fuzzed app writes to stderr becomes a
  `.correctness` finding with signature `app-stderr: <first distinct line>`
  (timestamp, process name, pid, and thread stripped so it is stable across
  runs); the detail counts the distinct lines, capped so a runaway logger cannot
  bloat a report. A missing log is silence only when the app never emitted
  telemetry; otherwise it is an `automation` finding named `stderr-log`. The
  scan reads at most 4 MiB and says so when it truncates. A crash still yields
  its crash finding plus an `app-stderr` finding when it wrote to stderr.
  `StderrScan.allowedSubstrings` is the allowlist. Its `Runner.swift` hunk is
  compile-checked only, and the `absentIsEmpty` rule lives there without a unit
  test.
- `fuzzfix/table-reentrancy` made no change, deliberately. The NSTableView
  warning is SwiftUI's own `List` on macOS 27, not app code: the app has no
  NSTableView delegate (`FontFamilyPicker.swift` and
  `CharacterSearchPicker.swift` use `List(..., selection:)`), and a bare `List`
  of `Text` rows with no selection or accessibility reproduces it. The trigger
  is creating a `List` with about 300 or more rows: in a standalone app, a newly
  created `List` logged the warning once at 300, 700, and 3000 rows and not at
  20, 100, or 200. A `List` already on screen that grew from 1 to 700 rows
  (three times) did not warn; an earlier claim that growth warns came from the
  test-host probes and does not reproduce standalone. Shrinking and reordering
  never warned, and a `ScrollView` with `LazyVStack` did not warn on
  presentation. In the fuzz run both warnings were creations of the roughly
  700-family `List`: opening the picker, and clearing a query that matched
  nothing, because `FontFamilyPicker.swift:86-90` replaces the `List` with an
  empty-state view when no family matches and builds a new one when the query
  clears. Nothing app-side can be fixed short of replacing `List` in both
  pickers, which would be a large change: the tests find the table through
  `host.subviews` and the fuzzer targets the picker as an `AXOutline`.
  - Possible mitigation, unverified and a UI behavior change: creation is what
    warns and growth does not, so keeping the `List` mounted (an empty-state
    overlay instead of swapping views) would avoid the second warning, and
    creating it with a first slice of rows and adding the rest a run-loop turn
    later might avoid the first. Not done.
  - Decision: accept it for now, and allowlist that exact line in `StderrScan`
    so runs that open a picker do not each produce a finding for something the
    app cannot act on. New stderr text is still a finding, and if the warning
    becomes an assert the resulting crash is a crash finding.
  - Report it to Apple with Feedback Assistant. A standalone Xcode project
    reproduces it (one window, one `List`, `--rows N`), verified on macOS 27.0
    (26A428) with Xcode 27.0 RC in the matrix above; it is not in the repo.
    Filed on 2026-09-29 as FB24998057 with the project attached. It was built in
    the session worktree under `.build/feedback/ListReentrancyRepro` (with a zip
    beside it); rebuild it from the description above if that directory is gone.
    Check the report's status when re-probing on new releases.
  - Re-run the probe on each new Xcode or macOS release. If it becomes an
    assert, both pickers crash on first open with a large family list, and
    replacing `List` becomes necessary; keep a stderr-capture regression test
    (`dup2` fd 2 onto a temp file around the interaction and assert that
    "reentrant" does not appear) for that rewrite.
  - Unverified: macOS 15 and 26, and whether `LazyVStack` clears it under filter
    growth.

## Smoke test of main at 153d978 (host, one minute, 2026-09-29)

Nine executions (five exploration, four seed). Artifacts were in the worktree's
`.build/smoke-ui-fuzz`.

- Liveness works. Seed runs take about 1.4 s (5.5-6.9 s before). Duration minus
  workload minus discovery is 1.0-1.4 s per run (5.2 s before). `quit-ms` has a
  median of 50 ms. No run reported a crash.
- Output capture works inside the LaunchServices-launched app: all nine runs
  have `stdout.log` and `stderr.log`, created by the app.
- Its first catch: run `649e2831` wrote
  `WARNING: Application performed a reentrant operation in its NSTableView delegate. This warning will become an assert in the future.`
  to stderr twice. The run's tail is font-picker interaction (press
  `Font B family`, two `Search installed fonts` values, the search field's
  cancel button). It turned out to be a SwiftUI `List` warning, not app code
  (see wave 3 above).
- Four of five exploration runs completed all 32 actions (36% did before). The
  one abort was `Control not found: [0, 0, 20, 7]`, the tracking-edit case the
  ranking change does not cover. Too few runs to call it a rate.
- Three runs were force-quit after about 2 s: two ended with the Match sheet
  open and one ended with a pop-up menu open (a press on
  `Character Alternatives`). So any open menu or sheet holds up the polite quit,
  which points at a driver artifact more than an app bug. Escape before the quit
  would recover the 2 s, but it would also stop measuring this until the hand
  check (Shift-Cmd-E, then Cmd-Q) settles whether users can quit with a sheet
  open.
- Exploration runs take 13-15 s in total, of which discovery is 2.1-6.0 s
  (16-46%). Discovery cost is the largest throughput lever left. The resolver
  rewrite that touched the same code has merged, so it is no longer blocked;
  re-measure first, since `AXDiscovery` changed.
- Not exercised: crash detection and crash reports (needs a real crash: kill
  `TypefaceOff` with `-SEGV` mid-run) and the mutation model (mutation starts at
  execution 37).

## Smoke test of main at 4425485 (host, one minute, 2026-09-29)

Seven executions (four exploration, three seed), run before the mouse-delivery
merge, so clicks were still inert. Artifacts were in the worktree's
`.build/smoke2-ui-fuzz`.

- The resolver works. No automation finding (one of nine before). All four
  exploration runs completed 32 of 32 actions, every resolve succeeded on the
  first path attempt (0 retries, 0 skips), and the skip ledger has no failure.
- No crash. `stdout.log` and `stderr.log` exist in every run; `stderr` is empty
  in all seven, so the SwiftUI `List` warning did not fire and its allowlist was
  not exercised.
- Timing: seed runs take 1.7 s (1.4 s before). Exploration takes 15-16 s in
  total: about 7 s of actions, 1.2-4.7 s of discovery (130-175 ms per discover
  with 144-149 elements), 2.9-3.9 s of idle waits (about 100 ms each).
  `ax-read-errors` is 14-86 per exploration run, about 2-3 per discover.
- Blind behind sheets: not fixed by the merged `WindowScope` (see the section
  below). Two of four exploration runs opened the Match sheet and spent 22 and
  25 of 32 actions in the menu bar.
- Forced quits: two of four exploration runs (`quit-ms` 2026-2039), both with
  the Match sheet open at the end; three of five before.
- A probe explains the quit (`.build/probes/quit-with-sheet` in the worktree,
  untracked, macOS 27.0.1). A quit request sent while any sheet is open is
  dropped, not deferred: `applicationShouldTerminate` is never called, and a
  request sent before the sheet closes is not rescued when it does. A fresh
  request after the sheet is gone exits in 10-40 ms. A minimal SwiftUI app with
  a `.sheet`, an AppKit `beginSheet` panel, and an `NSApp.runModal` panel all do
  it, through the quit Apple event, `NSApp.terminate`, and posted Cmd-Q. The
  real app with the Match sheet open never quit in 8 of 8 valid runs; without a
  sheet it quits in 24-115 ms. An open menu only delays the quit (0.03-3.8 s).
  The app has no delegate or termination code of its own. The platform knobs are
  `.presentationPreventsAppTermination(false)` (macOS 15.4 and later; the
  deployment target is 15.0, so it needs an availability check) and
  `NSWindow.preventsApplicationTerminationWhenModal = false`; with either the
  quit exits in about 40 ms. Left alone: a user's Cmd-Q with a sheet open does
  nothing, which is the platform default that protects sheet edits. Decided
  2026-09-30: the app stays as it is and the driver dismisses overlays before it
  quits.

## Merged to main: wave 4

- Sheet scope (`Discovery.swift`, `WindowScope.swift`, `TreeDump.swift`): see
  "The explorer is blind behind sheets". Followed by fail-closed discovery when
  an overlay has focus but is not found, `unlocated` in the driver log, and the
  `standardWindow` focus location. Two tests were pinned by mutation checks (the
  `if live` guard in `TreeDump.capture` and the offered-only rule for role
  candidates).
- Quit hygiene (`QuitPreparation.swift`, `Runner.swift`): before the quit the
  driver presses Escape while `Discovery` reports an open or unlocated overlay,
  at most three times, polling up to 0.5 s after each. It quits regardless and
  reports it. Metadata: `quit-overlays-dismissed` (the number of Escapes sent),
  `quit-overlay-remaining`, and `quit-dismiss-ms`; `quit-ms` and `quit-forced`
  keep their meaning, and all three keys are absent when the preparation is
  skipped (watchdog, app already exited, desktop unavailable). One `Discovery`
  capture per run costs 40-200 ms. A failure to send the key is an `automation`
  finding with signature `quit-dismiss`, not an availability finding, so the
  campaign does not discard a run whose actions all completed. Limits: a
  timed-out accessibility read looks like no overlay (read errors are common, so
  they are not treated as an open overlay), the heartbeat is not rechecked after
  the Escapes, and the startup-telemetry failure path still runs the preparation
  against a hung app.
- Sheet-aware mutation (`MutationState.swift`, `Trace.swift`,
  `Discovery.swift`): discovery tags each action it offers inside a sheet with
  the new optional `FuzzAction.sheet` (`match` or `editor`), told apart by
  `Cancel matching` or `xmark.circle.fill` for the Match sheet and
  `Custom specimen text` for the editor. A tagged action requires its sheet, so
  `repaired` inserts the opener for font-dependent axis and feature names too;
  untagged actions fall back to a name table of the fixed Match controls. The
  model knows the closers `Cancel matching` and `xmark.circle.fill`, and the
  openers `Match fonts…` and `Edit sample text…`. Return in the Match sheet
  leaves the sheet state unknown because `Apply` is disabled until a fit
  improves, so the next requirement presses Escape first. On synthetic 32-action
  explorer traces, 12.9% of 3,000 mutants used a sheet control with no sheet
  open; it is 0.0% with tags and 2.7% (the axis and feature toggles) with the
  tag withheld.

Still to verify in a live run (the smoke test of `50cdf05` below settled the
rest): the editor sheet's `sheet` tag and `Custom specimen text`;
`AXPress failed` automation findings on `Cancel`, `Apply`, and
`Cancel matching`, which no run has pressed yet; and `unavailable` findings with
signature `activation` on otherwise clean runs (a key posted at quit calls
`activateIfNeeded`).

## Smoke test of main at 50cdf05 (host, one minute, 2026-09-30)

Seven executions (four exploration, three seed), the first with mouse delivery
merged. Artifacts were in the worktree's `.build/smoke3-ui-fuzz`.

- The accessibility shape is settled. With the Match sheet open every `discover`
  event reports scope `overlay`, `focusLocation` `scopeWindow`, `focusedRole`
  `AXSheet`, `modalRole` `AXSheet` at depth 2, and `sheet` `match`, and
  `unlocated` was false in all of them. `AXFocusedWindow` is the sheet and the
  tree nests it inside the scope window. A context menu opened in the sheet is
  an `AXMenu` at depth 6 or 8, nested under the text area that opened it; the
  font popover is an `AXPopover` at depth 4 while the window keeps focus.
- The explorer now works inside sheets: 23-25 elements offered, and it pressed
  `Stop`, clicked `Refine`, scrolled the sheet's specimen areas, and opened
  context menus on its text areas. Seven actions carry `"sheet": "match"`. No
  run pressed `Cancel`, `Apply`, or `Cancel matching`, and the editor sheet did
  not come up.
- Quit: no forced quit in seven runs (two of four before), `quit-ms` 28-75 ms.
  The two runs that ended inside the sheet, one with a menu open in it, sent two
  Escapes (`quit-overlay-remaining` false) and spent about 1.1 s in the
  preparation: after the first Escape closes the menu the loop waits out its
  whole 0.5 s window, because the sheet is still open, before it sends the
  second. Runs with no overlay spent 66-123 ms. Waiting only until the overlay
  changes would save most of that.
- Two of four exploration runs ended in `locate click target failed: -25212`, a
  click on a context-menu item inside the sheet (`Start Speaking`,
  `Substitutions`). The tree nests that menu in the scroll area of the text that
  opened it, and `AXDriver.center(of:)` clipped the item by that scroll area,
  which is empty where the menu is. It stops at an `AXMenu` or `AXPopover` now,
  as `VisibilityRules` does. It was invisible before mouse delivery, because
  clicks were inert.
- The resolver is healthy: no skip, no retry, every resolve by path, no failure
  in the skip ledger.
- Timing: a discover takes 118 ms median with no overlay and 187 ms (72-320)
  with a sheet, because discovery walks the whole window; one popover discover
  took 1.1 s. Idle waits are 150 ms median. Together they are about 8 s of a
  15-20 s exploration run.

## Smoke test of main at a3c14d8 (host, one minute, 2026-09-30)

Seven executions (four exploration, three seed), with the click-point fix.
Artifacts were in the worktree's `.build/smoke4-ui-fuzz`.

- `locate click target` is gone (two of four exploration runs before). The
  click-point change is confirmed only by the absence of the failure; no run
  clicked a context-menu item.
- The editor sheet was explored for the first time: `Shift-Cmd-E` opened it,
  discovery tagged it `editor` after one `unidentified` discover while it was
  still animating in (2 elements, no controls yet), the explorer typed into
  `Custom specimen text`, scrolled, pressed `Cancel` (no `AXPress` failure), and
  carried on in the workbench. The font popover was explored too (`cancel`,
  `Search Unicode characters`, Escape).
- One automation finding, `AXPress failed: -25200` on a press of `Match…` at
  action 21 of 32. The sheet had opened, as in the earlier analysis: the SwiftUI
  accessibility proxy reports failure after the action is dispatched. About one
  in nine presses of it does this (3 of 26 before; 1 of the 2 presses in the
  last two smoke tests), and it ends the run, so it costs the sheet exploration
  the button exists to reach. Proposed: read `AXEnabled` on -25200, count an
  enabled control's press as dispatched but unconfirmed in the ledger and run
  metadata, and continue; a disabled control (Zoom at its limit) becomes a skip.
  It turns a fail-fast error into a counted one, so it waits for a decision.
- One forced quit (`quit-overlays-dismissed` 3, `quit-overlay-remaining` true,
  `quit-dismiss-ms` 1.8 s). The run opened the Match sheet, a context menu on
  its text area, pressed `Writing Tools`
  (`__NSTextViewContextSubmenuIdentifierWritingTools`), and Apple's Writing
  Tools popover (an `AXPopover` at depth 6) and then a nested `AXSheet` at depth
  3 appeared, which three Escapes did not close. The same NSTextView context
  menus offer AutoFill (Passwords, Contacts, Credit Cards), Share, Look Up,
  Translate, Speech, Show Fonts, Show Colors, and Show Spelling and Grammar, all
  of which open UI outside the app, and some prompt for credentials on the host.
  The Apple-menu items (Log Out, Lock Screen, Force Quit) are pruned because the
  Apple menu is not in `allowedMenus`, and were never offered in the dumps.
- No crash; the resolver has no skip, no retry, and no ledger failure.

Follow-ups from wave 4 and these smoke tests: workbench controls with no
requirement in the table (Swap fonts, Font A Size) can still run while a
mutated-in opener has a sheet up (they usually still resolve, so the harm is
small; a `sheet closed` requirement would fix it); menu-item actions such as
`Match fonts…` need their menu open, which the model does not track, so deleting
the preceding `Comparison` press strands them like a sheet opener;
`resolveRecordedSlot` never skips a recorded action that cannot resolve (right
for replays; `repaired` should drop such actions if mutants keep producing
them); `Apply` and `Refine` depend on fit state and `Stop` exists only while a
fit runs, none of which the model tracks; `TreeDump` does not record `unlocated`
or the modal root, only the per-entry `offered` flags; `driver.jsonl` records
nothing about the pre-quit checks; the pre-quit loop could send its next Escape
as soon as the open overlay changes instead of waiting out the window.

## Not started

### Startup self-test (judgment finding)

Run a short built-in suite before the campaign loop and abort loudly when an
expectation fails: Cmd-2 gives glyph mode; Cmd-2 then a click on `Glyph canvas`
gives text mode; Shift-Cmd-E, a value, and Apply make `textUTF16` equal the
typed length; a killed dummy child is seen exiting within 100 ms. Use
`precondition` or `try!` on executed lines. This would have caught three of the
four blind spots in the first minute. It depends on the mouse, liveness, and
custom-text fixes landing first.

### Custom-text stress path (VP5, VB5)

99.6% of snapshots (4,795 of 4,816) have `textUTF16 = 22191`. The generator
emits `setValue` on `Custom specimen text` without opening the editor sheet, so
none of the 100,000-unit texts ever land (58 attempts, 38 failed, none applied
at 4,096 units or more). Make it one compound action kind (open editor, set
value, press Apply) like `selectFont` (`AXDriver.swift`), so `mutate()`,
`constrained()`, and `TraceReducer` cannot split it. `constrained()`
(`Generation.swift:139-150`) must bound the new action or `--max-text-units` is
bypassed. It touches `Trace.swift` and `AXDriver.swift`, which the merged
resolver rewrote; no longer blocked, but re-read them first. Note that discovery
now offers only an open editor sheet's controls (not yet seen in a live run), so
the compound action may simplify.

### Runtime warnings and the dead exit status (VB1, F2, remainder)

App stdout/stderr and crash reports are captured, and anything on stderr is now
a finding (waves 2 and 3 above). What remains: fuzz builds are release
configurations, so debug-only SwiftUI runtime warnings may never appear (verify
with a known-warning build), and whether `OS_ACTIVITY_DT_MODE=YES` routes
`os_log` to stderr is untested; a post-run
`log show --predicate 'subsystem == "com.apple.runtime-issues"'` is the
fallback. Normalize hex addresses and other per-run numbers in stderr messages
so their signatures stay stable. Output written before `FuzzDiagnostics.shared`
is first touched is not captured; touch it early in `TypefaceOffApp.init`. The
dead `ExecutionReport.exitStatus` (constant nil, never encoded) should be
dropped or filled from the crash report's termination code; that touches
`Trace.swift`, which the resolution session edits.

### The explorer is blind behind sheets (investigation, wave 2)

Status: believed fixed in code, verified only by unit tests; not yet seen in a
live run. The merged `WindowScope` did not fix it. In the one-minute host smoke
test of `4425485` (2026-09-29, `.build/smoke2-ui-fuzz`), every `discover` event
with the Match sheet open reported scope `overlay` with 1-12 elements, all
menu-bar items and their menu items, and no action targeted a sheet control (25
of 32 actions in run `3bf4737e`, 22 of 32 in `5d51a6cd`). The cause, read from
the code because the live tree has not been dumped, was
`WindowScope.discoveryIncludes`: with a sheet up `AXFocusedWindow` is evidently
not a standard top-level child, so discovery dropped the standard window, and
the sheet nested inside it, and kept only the menu bar. Discovery now walks the
scope window and every non-standard top-level child. When the focused overlay is
found in that walk, its subtree is the modal root, whether the tree nests it in
the window or lists it beside it. A sheet, popover, or open menu that does not
hold focus still narrows by role; the deepest candidate wins and the focused one
wins ties. Only the modal root's controls are offered, plus plain keys (Escape
included) and no shortcuts. When an overlay has focus but is not found in the
walk and no offered sheet, popover, or menu backs it up, discovery fails closed:
it offers only the plain keys, no elements and no shortcuts, because anything
else could act on controls the user cannot reach behind a modal. Discovery and
`TreeDump` share `ModalScope.selection`, so the dump's `offered` flags agree,
and resolution shares `WindowScope`. Each `discover` event in `driver.jsonl` now
records `focusedRole`, `focusedSubrole`, `focusLocation`, `modalRole`,
`modalDepth`, and `unlocated` (true for the fail-closed state), so the next live
run shows the real shape. `focusLocation` is `standardWindow` for an ordinary
focused window, `applicationChild` for a non-standard overlay listed beside the
windows, `scopeWindow` or `otherChild` for one nested in the scope window or
another top-level child, and `notFound` when discovery did not traverse the
holder. Check on the next live run that actions land inside sheets (presses of
`Apply`, `Cancel`, `Refine`, `Stop`, and values in the editor field), which were
zero in 536 exploration runs before, and count the `discover` events with
`unlocated`. Discovery under a sheet now walks the whole window. Non-sheet
discovers in the smoke test took 90-237 ms; sheet-state discovers before this
change took 4-62 ms, because they walked only the menu bar.

Known limits:

- The scope window is `standard.first`, the first standard window in
  `AXChildren` order. A sheet on a non-front window, for instance after Cmd-N,
  is not found, so that state is `unlocated` and the explorer presses plain keys
  until Escape closes the sheet. Run `5d51a6cd` shows `windows=2`, so expect
  `unlocated` discovers after Cmd-N; they are this limit, not a discovery bug.
- Modal precedence is by path depth, a proxy for z-order, not by z-order.
- `Resolver.isOffered` ignores modal scope, so a same-named control behind the
  sheet can make a stale live pick ambiguous.
- A press that closes a sheet may report `AXPress` -25200 and end the run as an
  automation finding. Watch the next live run for `AXPress failed` on `Cancel`,
  `Apply`, and `Cancel matching` before trusting the abort rate.
- Discovery under a sheet walks the whole window, which took 90-237 ms in the
  smoke test's discovers without a sheet.

146 of 536 exploration runs opened the Match sheet or the custom-text editor
(Shift-Cmd-M, Shift-Cmd-E, or a press on `Match...` or `Edit text`). Between
that opener and the next Escape, Cmd-N, or closer, 1,664 actions were menu, key,
or shortcut actions and only about 300 were window controls, against a baseline
of about 82% window controls. Across all 536 exploration runs there is exactly
one action inside a sheet (a `setValue` on `Custom specimen text`) and no press
of `Apply`, `Cancel`, `Refine`, or `Stop`. Shortcuts are offered only when no
modal is detected, and 315 were offered while a sheet was up, so the sheet is
not detected as modal.

Still open: dump each menu item's `AXEnabled` and `AXFrame` when a menu is
detected but nothing is offered, and add a FuzzDiagnostics `sheet` event (kind,
open or closed) so analysis needs no reconstruction.

Consequence for the menu: every menu-bar press in exploration happened with a
sheet up, and the app deliberately disables all workbench commands then
(`WorkbenchView.swift:118`, `focusedSceneValue` is nil while
`showMatch || showEditor`). That is why no app-defined menu item was ever
offered. The commands work without a sheet (Cmd-Opt-S swapped fonts in 73 runs
that no other route explains). Once the explorer can see sheets, add seeds that
press `Comparison` then `Match fonts...`, `Swap fonts`, and
`Edit sample text...` with no sheet, and keep `click` on a menu-bar item from
being counted as an opener (it never opens a menu; that is the mouse-delivery
problem).

### Campaign event log, ledger, and provenance (B1, VR4, VI4, VI5, VI6, F7, F8, F11)

- Append-only `campaign-events.jsonl` (process start with pid, seed, argv, build
  id; desktop transitions; availability attempts; stop reason), written with
  `try!` on a line that also runs normally. The overnight 2026-09-28 outage was
  a 7.5-hour retry loop on execution 20 that no artifact records; the lock cause
  is already closed by `d03d52f` and `91baf55`, the persistence is not.
- Per-execution ledger (`executions.jsonl`) with timings, so questions about
  coverage growth and waste need no re-run.
- Provenance in every report: app commit, binary hash, font catalog identity,
  macOS build, VM image, driver commit. Refuse to resume coverage state across
  app builds.
- `fuzz-replay` and `fuzz-minimize` give no verdict and silently drop or bypass
  trace version checks; make them report reproduced or not, with a rate.
- New `ExecutionReport` fields must be Optional because loading deletes reports
  that fail to decode.

### Slow-finding rework (B3, VR3, VP6, VP11, C5)

The top-20 is a length filter: 19 of the 20 have 30 or more actions against
15.8% of clean runs, ranked by `measuredMilliseconds` (workload minus pacing).
The detail text is constant, so a finding carries no time, rank, or action.
Heartbeat gaps over 800 ms (7 runs) all fall in cold-boot windows or the
09:44-10:05 window when the host ran `make test` and a fuzz build, so latency
samples are contaminated by host activity. Proposed: record per-action start
uptime (Optional field), guest boot age and a host-busy flag in metadata; rank
by per-action or normalized time and put the measurement in the detail; add a
main-thread-stall criterion (largest heartbeat gap over about 400 ms, attributed
to an action). Stall findings must not use kind `slow`, because
`preserveFindings` skips it. Driver bookkeeping (rewriting `executed.json`,
re-parsing telemetry after every action, on the host share in the VM) sits
inside the timed workload; subtract or move it. Decision needed: changing the
rank changes what the leaderboard means.

### Signatures and failure diagnostics (VT7, VB4, VI11, A5)

Signatures embed positional paths, so 85 distinct strings cover about 13
clusters and 5 causes. Suggested: `unresolved:<lookup>:<role>:<kind>` plus a
cause tag. The "Visible accessibility elements" list is the first 100 names in
alphabetical order (30% `AXMenuItem`, never a text field, slider, or scroll
area) and includes the Apple menu; host data listed recent file names from it.
Replace it with a structured dump of the focused window. Finding files are 87.5
MB, 88% of it duplicated coverage arrays.

### State coverage and seed schedule (D2, VC5, VP12, VB6, VC12, D6)

- Mutation starts at execution 37 and seeds 9-17 run at executions 19-35. Run
  all 18 seeds first for short campaigns.
- Widen state where behavior and latency are decided: fonts (`selectFont` in
  exploration, a font zoo), samples (changed in 13 of 1,071 runs), calibrated
  size links, variable-font axes, removing font B, and the missing-font state,
  which the project rule says must be visible.
- Corpus admission counts any new bucket; count bucket-only admissions in the
  ledger (38% of admissions in the logged window) before changing
  `Corpus.swift:7`.

### Storage (VR7, VI7, B9)

`coverage.profdata` is 75% of `runs/` (about 1.5 GB for 1,071 runs) and finding
files are mostly coverage arrays; nothing prunes. Keep profdata only for runs
that added coverage.

### App performance (C2, VP4, C3, VP2, E11, VP8, VP9, VP10, C4, E12)

Each size or tracking commit rebuilds both 22k-character specimens (six renders,
about 168 ms), which matches the 170-380 ms tail on slider actions. The figures
predate the startup-work merge; profile a release build before designing
anything (adapt `scripts/profile-startup.sh`). Smaller items: `Comparison.text`
rebuilds a 22,191-character string on every access (`Samples.swift:17`,
`Comparison.swift:141`, 7-9 times per body pass) and `Differences.highlights`
rebuilds a `Set` per call (`Differences.swift:123`), together worth about 47 ms;
presenting the editor sheet with the full text blocks the main thread about 0.4
s; `CharacterSearchIndex.shared` could be prewarmed at low priority; cap Match
concurrency and lower its QoS. Keep scalar-exact keys and the per-side
independent configuration.

### App oddities: what the investigation found

- The Comparison menu items "never selectable in about 160 openings" are not an
  app bug: see the previous section. The sheet disables them on purpose.
- The polite quit is ignored for 2 s in 141 of 1,071 runs, and it is
  deterministic: 56 of 56 runs whose last sheet opener was never closed ignored
  it (editor 26, Match 30), against 0 of 17 where a `Cancel`, `Apply`, or
  `Cancel matching` followed, and 15 of 845 (1.8%) with no opener. Nothing in
  the app implements `applicationShouldTerminate` or a confirmation, so the
  cause is AppKit or SwiftUI window-modal sheet behavior. Unverified whether a
  user can quit with a sheet open. By hand: open the editor (Shift-Cmd-E), press
  Cmd-Q, and also run
  `osascript -e 'tell application id "<bundle id>" to quit'`; if only the Apple
  event is ignored it is a driver artifact, and if both are ignored it is
  standard sheet behavior and arguably not a defect. Either way the driver
  should press Escape (or skip the polite quit and force-terminate) when a sheet
  may be open, which recovers about 2 s on 13% of runs; coverage survives the
  forced exit (`coverage.profdata` was written in all 141 forced runs).
- The three `AXPress failed: -25200` on `Match...` are a harness artifact: the
  button was enabled (fonts available), the sheet was presented (its controls
  are in all three failure snapshots), and the SwiftUI accessibility proxy
  reported failure after dispatching the action, as
  `WorkbenchInteractionTests.swift` documents ("Callers verify the resulting
  model or view state"). 3 of 26 presses with no prior sheet failed. A driver
  fix would read `AXEnabled` on `-25200` and report a distinct finding without
  aborting the run; it changes fail-fast semantics for 0.3% of runs, so it stays
  low priority. `Zoom in`/`Zoom out` at the limits are the other cause: those
  buttons really are disabled.
- Shared size and Character fields commit only on Return, and out-of-range size
  is silently clamped to 10-144 (`Comparison.swift:42`; `setValue "0"` produced
  size 10 in finding 1). Commit-on-blur, a visible clamp, or rejection are
  product decisions and existing tests pin the current behavior (E4).
- Glyph navigation from a character absent from the list skipped the first entry
  (E14): fixed in wave 2. The second half of VB11 is open: while
  `RankingModel.update` has cleared scores (the first 130-330 ms after an edit
  with a second font), navigation follows the alphabetical candidate list, not
  the rank order. Options: keep the previous ranking for navigation until the
  new one arrives (stale after a font or sample change), ignore navigation while
  comparing, or keep the old scores visible until replaced.
- The font picker's Return re-selects the current row while typing, which breaks
  seed 8 (E13).
- `GlyphNavigationTests.focusFeedbackFollowsTheCanvasAndWindow()` can report a
  QoS priority-inversion runtime warning, which makes `scripts/test-app.sh` exit
  1 when that whole suite runs. Check whether it is flaky or new on Xcode 27.

### Infrastructure (VI3, VI10, F10, VI12, B11, F5, VI8, VP14, VP15, VB12)

- A second guest doubles throughput (Apple allows two macOS guests; use
  `tart clone typefaceoff-fuzz <name>` and `FUZZ_VM=<name>`).
- Harden `scripts/fuzz-vm.sh`: liveness detection, bounded waits, stale-VM
  adoption, IP-based ssh assumptions.
- Host campaigns hold no keep-awake assertion, so display sleep and lock pause
  them.
- Discovery costs about 115 ms per pass at 7-12 AX round trips per element;
  batch attribute reads and prune long lists. The completion check can declare
  idle while the last key or shortcut is still queued.
- README: document VM campaign behavior and limits.

### Explorer budget and identity (VC9, VT5, VP13, VB8)

Visit counts key on positional paths, so index drift fragments them and the map
grows without bound. About 20% of exploration actions go to macOS-owned menu
items (Apple, File, Window, Help). Discovery prefers identifiers over titles.
Window-title-derived tab labels make recorded targets state-dependent.

### Availability (B2)

Availability retries are unbounded. Add attempt counters and `firstFailedAt` to
the metadata of `availability.json` (not new report fields).

## Decisions taken (2026-09-29)

Delegated to judgment; revisit any of them with the evidence named.

- Command-N stays in the explorer and mutator. Multiple windows are a real
  feature and a crash or hang there is worth finding. After Command-N the
  per-step failure rate is 4.5% against 3.2% (not significant); it matters only
  through duplicate labels across windows (about 28 findings, 4.7%). The fix is
  in resolution (scope to the focused window, wait for the new window's
  workbench), which the resolution session owns.
- Continuing past an unresolved step (VT8, A10) is acceptable only when each
  skip is counted and surfaced, as the resolution session's `SkipLedger` does.
  Until that lands, an unresolved step stays a finding.
- Automation findings stay in `findings/` (B5, VR8). After the resolver lands,
  measure the harness-invalid rate and add an abort above a threshold over a
  window, chosen from that measurement, so a blind harness fails loudly.
- Mouse delivery: try click state and window fields first (local, no cursor
  movement, safe on the host and in the VM), verifying on macOS 26 as well
  as 27. Real HID events only in the VM and behind an explicit flag. Do not
  substitute `AXPress` for clicks.
- The "Comparing glyphs" indicator: restarting ranking on edits that do not
  change its input is fixed. For tracking, font, feature, and text edits,
  re-measure after the resolver lands before changing the accessibility tree;
  keeping the indicator permanently needs an AX dump and a VoiceOver check.
- Slow ranking: keep the top-20 leaderboard, rank by time per action, and put
  the measurement, rank, and slowest action in the detail; give stalls (a large
  heartbeat gap) their own finding kind. Do this after the resolver lands, since
  both touch `Runner.swift` and `Trace.swift`.
- Size input: keep the clamp to 10-144 pt (the native range) and make it visible
  later with help text or an announcement. Rejecting would change behavior that
  existing tests pin and discards the value the user meant.
- A launch that dies five executions in a row stops the campaign (wave 2).
- Crash detection after a driver error stays as is until a real crash shows the
  ReportCrash case.
- The mutation model gaps (font B presence, inspector visibility, the Match
  sheet's `Apply` and `Weight`) wait for the next campaign: Font A/B controls
  fail about 2% of the time in the data.

## Considered and set aside

- "Character search is unreachable" (D7): an artifact of the 19-execution
  window; the VM campaign covers 529 regions in `CharacterSearch*`. The
  remaining gap is query variety.
- A stop rule on coverage plateau (VR10): the tail is bursty and the longest gap
  without a new region was 101 executions, so a useful threshold would never
  fire. Spend effort on state coverage instead.
- Attributing latency outliers to AppKit menus or app code (VP13): they coincide
  with host activity and cold boot; replay on a quiet host first.
- Dropping `.click` from controls that support `AXPress` as the mouse fix: it
  loses the only accidental mouse coverage until delivery works.
- Cmd-N as the main cause of stale paths: only about 28 findings; the dominant
  cause (57% of findings) is index drift from the transient "Comparing glyphs"
  indicator after size and tracking edits.
