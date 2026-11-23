<!--
Copyright © 2026 Michael Shields

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
-->

# UI fuzzing

`make fuzz` explores the running app’s controls and mutates recorded action
sequences. It saves cases that add coverage or expose failures, hangs, and slow
actions under `.build/ui-fuzz`. Stop the campaign with Ctrl-C, or set a time
limit and seed:

```sh
make fuzz FUZZ_ARGS='--seed 42 --duration 10m'
```

The driver needs an unlocked desktop and macOS Accessibility and event-posting
permissions. On first use, enable `.build/fuzz-driver/UIFuzzDriver.app` in
System Settings when prompted. The driver relaunches and continues. Set
`FUZZ_ARTIFACTS=…` to keep a separate campaign or replay directory. Each
execution requires 512 MiB free on both the artifact and temporary volumes by
default. Use `--minimum-free-space-mib` to change the threshold.

Clicks, drags, and scrolls are real mouse events posted through the session
event tap, because AppKit silently drops mouse events posted to the app’s
process. They move the real pointer to each target, so leave the mouse alone
while `make fuzz`, `make fuzz-replay`, `make fuzz-minimize`, or
`make fuzz-benchmark` runs on this Mac; only `make fuzz-vm` campaigns run in the
guest. Before each click, drag, or scroll the driver activates the app and waits
for Accessibility to report the app under the target point. When the Dock,
another app’s window, or nothing is there, such as a control off the display,
the action fails as an automation finding instead of clicking elsewhere. The
finding keeps a stable signature and records the point, process id, and process
name that received the hit test.

## Run in a virtual machine

`make fuzz-vm` runs the same campaign in a macOS 27 virtual machine whose
session never locks, so it continues while this Mac is locked and keeps its
state under `.build/ui-fuzz-vm`. It requires [Tart](https://tart.run)
(`brew install openai/tools/tart`; Tart moved from Cirrus Labs to OpenAI in
2026), Xcode, and an unlocked login keychain, which macOS keeps unlocked while
the screen is locked unless Keychain Access is set to lock it. The guest runs
headless with only the system's fonts, uses this Mac's Xcode read-only for
coverage tools, and stops when the campaign does. Run `make fuzz-vm-setup` once
first: it clones Cirrus Labs' `macos-golden-gate-vanilla` image (about 35 GB) as
`typefaceoff-fuzz`, expands its virtual disk to 100 GB, shows the guest's window
while you allow UIFuzzDriver in its Accessibility settings, and runs a
one-second campaign to confirm the driver works. The disk image is sparse, so
the full virtual capacity is not allocated on the host. Both setup and each
campaign expand an older, smaller fuzz VM before booting it. Campaign setup
suppresses interactive CrashReporter dialogs in the guest; diagnostic reports
are still written and copied into crash findings. Guest timings are comparable
to this Mac's but are not interchangeable with them. A headless guest's display
boots at 1024x768 points, narrower than the workbench window, so each campaign
first switches it to 1920x1080 points, which fits the window and every control.

## Replay, reduce, and benchmark

Run these commands from the repository root, replacing the path with a saved
trace or finding report.

```sh
make fuzz-replay CASE=path/to/case.json
make fuzz-minimize CASE=path/to/case.json
make fuzz-benchmark CASE=path/to/case.json
```

`make fuzz-benchmark` measures the saved corpus in an optimized build without
coverage instrumentation. Set `CORPUS=…` to measure another directory. Timings
include only completed, successful executions. The benchmark waits for
quiescence after each action. To use that pacing in a coverage-instrumented
replay, add `FUZZ_ARGS='--wait-for-quiescence'`.

`actionLatencyMedianMilliseconds` reports median interaction latency for each
action. `actionMedianMilliseconds` measures control resolution plus dispatch.

## Campaign behavior

Before entering the campaign loop, the driver runs a self-test against fresh app
instances. It requires Command-2 to enter glyph mode, a real click on
`Glyph canvas` to return to text mode, and an editor submission to update the
reported UTF-16 text length. It also kills a dummy child process and requires
the liveness check to see the exit within 100 ms. Any failure stops the driver
before the corpus or campaign state changes; successful probe artifacts are
removed.

Exploration discovers visible, enabled controls in the focused window after each
action. Recorded paths, roles, and names identify the controls for replay.
Setting custom specimen text is one action through reduction and replay.
`--max-text-units` bounds the text that reaches the renderer.

When the desktop is unavailable, the campaign pauses. If it cannot find the
workbench controls, it retries with a delay that grows from five to 60 seconds.
`availability.json` and the associated run retain the latest availability
failure. These retries stay out of the corpus. The driver still records crashes,
hangs, and correctness failures during an outage.

Before each live exploration action, a campaign waits for the app to go quiet:
no open work, and `--quiescence-ms` (200 by default, at most 1000; zero disables
the wait) since the previous action, counting its delay. No wait lasts longer
than one second, an execution stops waiting after eight seconds in all, and the
report counts the waits that gave up in `idle-wait-timeouts`. The driver then
looks the chosen control up again by its recorded path and then by name within
the focused window, with up to three attempts in half a second. If the control
is gone, the driver skips the pick, discovers again, and chooses another;
skipped picks leave the executed trace, so replays and the corpus never contain
them. An execution skips at most `--max-skips-per-run` picks (five by default;
zero ends it at the first miss), at most two in a row, and each control once.
Every other failure ends the execution as before, including a tree that could
not be read completely, and so does a missing control in a recorded trace,
because replays, reductions, benchmarks, and mutations must reproduce it. A
stale path whose name still matches several controls is reported as
`Ambiguous control:` instead of `Control not found:`.

## Findings and logs

The campaign keeps `.profraw` and `coverage.profdata` for runs that add region
or hit-count coverage. It saves a representative report the first time it sees
each finding kind and signature. `finding-occurrences.json` records the count
and the first and latest executions and times.

Progress reports show completed and attempted actions and a count of skipped
picks. `measured-ms` covers the action sequence and resulting UI work, excluding
waits and skipped picks. `total-ms` includes startup, shutdown, and coverage
collection.

`skip-ledger.json` in the artifacts folder counts, across executions, how often
each control was found or missing; unnamed controls count together by role. A
named control that goes missing three times in a row, or any control that goes
missing at least five times on half of its attempts, is reported once as a
`Persistent stale control:` finding that ends its execution.
`make fuzz-minimize` cannot reduce it, because it summarizes many executions.
The ledger starts over when the app binary changes or with
`--reset-skip-ledger`, and a campaign lists its 10 most-missed controls when it
stops.

A finding’s detail gives the attempts, the app’s pending work, the window
searched, and the picks skipped earlier. Each run’s folder under `runs/` holds
`driver.jsonl`, which records the driver’s waits, discoveries, lookups, skips,
and failures on the same clock as the app’s telemetry, and
`diagnostics-<n>.json` for the first skip and for the control or action failure
that ends the execution: the tree the driver searched in document order, the
application’s top-level elements, the app’s telemetry, and which controls
discovery would have offered. A side file that cannot be written is a finding.

## Action timings

Every execution appends a compact record to `executions.jsonl`, including
availability retries and failures. `action-timings.jsonl` contains one lifecycle
record for every attempted action, including skipped picks. Its zero-based
`index` counts attempts, so it can differ from the retained trace index after a
skip. Timestamps use the same seconds-since-boot clock as app telemetry;
`start-uptime` and `startedAt` in the execution record anchor it to wall time.
Resolution and dispatch have separate start and return timestamps. Dispatch
covers the whole driver operation, including internal reveals in compound
actions such as `setSpecimen`. Missing dispatch timestamps identify unresolved
attempts.

Settlement requires no open work and a main-thread heartbeat at least 200 ms
after dispatch returns and after the latest app activity. `quiescentAt` is the
first heartbeat that proves this condition. `result` is `settled`,
`nextActionStarted`, `timeout`, or `appExited`. Ordinary fuzzing retains its
action pacing: a new attempt closes the preceding measurement even if work is
pending. The records are reconstructed once from app event timestamps at
execution end, so delayed telemetry writes do not change pending-work snapshots
at dispatch return or settlement. `pendingAtEnd` also preserves unfinished work
on timeout, exit, or interruption. Heartbeat gaps are clipped to each
measurement's interval, including the unfinished gap when the main thread stops
responding. Latency includes the 200 ms quiet period and heartbeat sampling
(normally 50 ms).

Specimen shaping, TextKit layout, accessibility-value rebuilding, tooltips,
specimen drawing, glyph envelopes, and glyph drawing emit paired `work-begin`
and `work-end` events with UTF-16 text length and a process-wide generation ID.
Related layout, tooltip, and drawing work shares its view update's generation.

`campaign-events.jsonl` records execution boundaries, periodic driver and
desktop observations, desktop transitions, availability retries, heartbeat gaps,
sleep/wake and session notifications, and the stop reason. Guest events carry
guest uptime; the VM wrapper adds host boot age, VM elapsed time, VM lifecycle,
and SSH connection boundaries to the same append-only file. Observation gaps
include wall and uptime deltas where available; a suspected suspension is
labeled as such, since a missing observation alone cannot establish its cause.
These journals survive availability-artifact cleanup and campaign resumption.
