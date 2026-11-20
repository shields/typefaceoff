# Typeface/Off

A native macOS typeface comparison workbench built with SwiftUI, AppKit, and
Core Text. Compare installed fonts in reading samples, inspect individual
characters, and see where their shapes and spacing differ.

## Run

The app runs on macOS 15 or later, but building it requires Xcode 27 with Swift
6.4 or later. Install XcodeGen for the app build; development checks also use
Bun, Node.js, Lefthook, zizmor, ShellCheck, shfmt, jq, and uv:

```sh
brew install xcodegen bun node lefthook zizmor shellcheck shfmt jq uv
make setup
make run
```

`make build` creates `.build/xcode/Build/Products/Debug/TypefaceOff.app`, signed
locally with an ad hoc identity by default. `make project` generates
`TypefaceOff.xcodeproj` for development in Xcode. `project.yml` owns the project
and app metadata; generated files are ignored. Signing entitlements are in
`Config/*.entitlements`.

To preserve macOS privacy permissions across development builds, create
`Config/Development.local.xcconfig` with your Apple Development identity:

```xcconfig
DEVELOPMENT_TEAM = YOUR_TEAM_ID
CODE_SIGN_IDENTITY = Apple Development
```

This ignored file applies to normal, fuzz, and benchmark development builds.
`Config/Signing.local.xcconfig` also supplies shared signing settings when
present. Ad hoc signatures identify each build separately, which can cause
repeated file-access prompts when running from a removable volume. A stable
signing identity lets macOS recognize successive builds as the same app; you may
need to grant permission once after switching identities. See Apple’s
[code identity documentation](https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements).

The app uses installed fonts. It makes no network requests and has no
third-party runtime dependencies. Install additional fonts with Font Book, then
reopen the app to refresh its catalog.

## TestFlight

Sign in to your Apple Developer account in Xcode, then create
`Config/Signing.local.xcconfig` with `DEVELOPMENT_TEAM = YOUR_TEAM_ID`. This
file is ignored by Git. Register `com.typefaceoff` and create a macOS app named
“Typeface/Off” in [App Store Connect](https://appstoreconnect.apple.com/apps).

Commit the release changes on `main`, then run:

```sh
make coverage
make lint
make archive
make testflight
```

`make archive` creates `.build/distribution/TypefaceOff.xcarchive` for Intel and
Apple silicon. `make testflight` creates a fresh archive and uploads it using
Xcode’s signed-in account and automatic signing. Archiving alone does not
upload. The app icon is packaged in `Sources/TypefaceOff/AppIcon.icon`.

Release versions use [gitcalver](https://gitcalver.org): `0.YYYYMMDD.N`, derived
from the release commit, with build number `YYYYMMDD.N`. Unlike iOS, macOS
[requires build numbers to increase across versions](https://developer.apple.com/documentation/xcode/preparing-your-app-for-distribution).
The vendored `tools/gitcalver.sh` is the unmodified
[v20260825.1 release](https://github.com/gitcalver/sh/releases/tag/v20260825.1).
Dirty working trees and commits outside the default branch are rejected. Each
upload needs a new commit; Xcode does not rewrite the version or build number.
Development builds use `0.0.0` with build number `0`.

The Release configuration selects `Config/TestFlight.entitlements`, which
enables the sandbox and an empty Keychain Sharing entitlement. Apple
[recommends the empty entitlement](https://developer.apple.com/forums/thread/733942)
to make Xcode embed the provisioning profile required by TestFlight.

After Apple processes the upload, configure test information and tester groups
on the app’s TestFlight tab. External testing requires TestFlight App Review.

### Bill of materials and notices

Install the archive tools with `brew install syft jq`. Both `make archive` and
`make testflight` generate `TypefaceOff.spdx.json` at the root of the finished
`.xcarchive`. Keep the report with its archive. Its file hashes describe that
particular build. CI runs the same checks on an unsigned universal archive and
publishes its report as the **TypefaceOff-sbom** workflow artifact.

Choose **Typeface/Off → About Typeface/Off → Acknowledgments** to open the
bundled text file in your default text viewer. Each build adds the Hyperglot
version, FineFreq commit, and Wikipedia revision from its data resources to the
reviewed attribution in [NOTICE](NOTICE).

The archive check verifies the notice against the bundled resources. Syft
inventories the bundle, and the link maps and load commands identify libraries
in each architecture. If the scan finds an unrecognized package or library, the
SBOM identifies it and the archive check stops the upload. When adding
third-party data, artwork, text, or code, update the attribution in `NOTICE` and
the source relationships in `scripts/app-sbom.jq`. For a local check,
`make ci-archive` builds an unsigned archive under `.build/ci-distribution`.

## Use

- Search either inspector’s font selector for an installed family, then choose a
  style. The selector focuses its search field; use ↑/↓ to highlight a result,
  Return to choose it, or Escape to dismiss it. Browsing leaves the current font
  unchanged until confirmation. Search for **None** in B to inspect one font;
  reselecting that family restores its previous settings.
- Appearance is linked initially. Size preserves the B/A ratio, and weight,
  tracking, and shared axes preserve their offsets, including after a range
  limit temporarily clamps a value. Unlock either inspector to adjust sides
  separately. Typography settings always remain independent.
- **Leading** sets the distance between text baselines in points (1–288).
  **Auto**, on by default, uses the font’s natural line spacing and displays its
  computed value. Turn Auto off to edit the value; turn it on or reset leading
  to restore automatic spacing. Explicit leading stays fixed when size changes.
  Linked leading preserves the point difference between explicit values,
  including after a range limit clamps a value. If either side is Auto when
  linked, entering a value sets both sides to that value; resetting either side
  restores Auto to both.
- Choose a reading sample or edit your own text. Enter a size in the center
  toolbar and press Return to set both sides. **Mixed** indicates different
  sizes.
- Open **Languages** (⌘3) to compare character coverage by language and script.
  The logarithmic speaker filter starts at 8.3M; historical records ship with
  the app and are hidden by default. Use **All** and **Show historical** to
  browse the complete catalog. **Use as specimen** creates an editable character
  sheet with one Undo step. See [language coverage](docs/languages.md) for the
  inventory policy, limitations, and data generation.
- Click a character in the text or difference strip to inspect it. Arrow keys in
  the glyph view navigate the ranked characters. Type a grapheme in the
  character field and press Return to inspect any Unicode character. Click the
  glyph canvas at 100% to return to the text, or choose **Text** (⌘1).
- Click the inspected character’s name, or choose **Find Character** (⌘F), to
  search by name (“left arrow”), by the character itself, or by code point
  (U+2192). Use ↑/↓ to highlight a result and Return to inspect it, or Escape to
  dismiss the search.
- In glyph view, use the mouse wheel, pinch gesture, or zoom slider to magnify
  the canvas from 100% to 800% without changing font settings. Zoom follows the
  pointer for wheel and pinch gestures. Drag or scroll with two fingers to pan
  when zoomed; click the percentage to reset to 100%. Zoom and pan stay fixed
  while navigating characters. Glyph outlines and their shared-ink intersection
  render as cached vectors; bitmap fonts use raster rendering.
- The overlay shows A-only ink in red, B-only ink in blue, and shared ink in
  black. Baseline, x-height, and vertical advance guides remain visible. Shape
  aligns left ink edges; Spacing alone aligns advance origins. Glyph scale and
  baseline stay fixed while navigating a sample. Advance and side bearings show
  native font units and em, independent of specimen size and added tracking.
- **Shape** and **Spacing** independently control highlighting and ranking.
  Scores use actual configured font shapes and metrics, including axes and
  substitutions. Ranking runs away from the UI thread, and obsolete requests are
  cancelled.
- **Frequency**, on by default, weights ranking and highlighting by how often
  each character appears in text worldwide, so a difference in a common letter
  outranks a larger one in a rare symbol. Each difference bar shows the weighted
  value over a faint track at the measured value, and a character’s tooltip
  gives its frequency and weight. Turn Frequency off to rank symbols, code, or
  less widely used scripts by measured difference alone. See
  [Character frequencies](#character-frequencies).
- In B’s font picker, switch **Name** to **Similarity** to rank installed
  families against A’s family. Both use the family’s regular face (normal width,
  weight nearest 400) with that instance’s axis settings, an optical size that
  follows A’s point size, default typography, and zero tracking. Lower distance
  means closer. Search filters the live results; pending and unsupported
  families remain selectable. Choosing a family carries B’s settings forward as
  usual, so its specimen can differ from the default settings used for ranking.
- **Match…** lists B’s axes, size, leading, tracking, and typography. Click
  **Optimize** beside a setting to search for its closest value while keeping
  every other preview setting fixed. Searches start only when clicked, and
  successive searches build on the preview. Each search uses up to 15 seconds or
  2,048 evaluations. A started comparison can finish after the time budget.
  **Stop** retains the best verified preview. Cancel discards it, and Apply
  changes only B in one undoable edit, recalibrating appearance links. Only
  improvements verified on the full fitting corpus can be applied.
- Browsing or searching glyphs, switching views, and toggling highlights
  preserve Undo/Redo. Undoing a font edit keeps the current inspection in view.
- Launching the app opens a fresh comparison window. Each window is independent;
  settings and sample text stay in memory and are discarded when it closes.
  Missing fonts and glyphs are labeled rather than silently compared using
  fallback fonts.
- Typography previews use examples that change with the selected font and
  feature. Some fonts’ ligatures apply to scripts other than Latin. Features
  without a verified example show **No preview available**.

The **Edit** menu’s Find Character (⌘F) searches for a character to inspect. The
**View** menu switches between Text (⌘1) and Glyph (⌘2), toggles the font
inspectors (⌥⌘1 and ⌥⌘2), and toggles Shape and Spacing highlights (⇧⌘1 and ⇧⌘2)
and frequency weighting (⇧⌘F). The **Comparison** menu offers Match (⇧⌘M), Swap
Fonts (⌥⌘S), and Edit Sample Text (⇧⌘E). Commands apply to the active comparison
window and are unavailable while its editing or matching sheet is open.

## Develop

```sh
make build
make test
make coverage
make lint
make fmt
```

`make fuzz` builds an optimized, coverage-instrumented diagnostic app and drives
its real macOS UI until interrupted. It checkpoints coverage-interesting,
incorrect, crashing, hanging, and slow action sequences under `.build/ui-fuzz`.
Campaigns alternate live UI exploration with coverage-directed trace mutations.
Exploration discovers enabled, visible controls after each action and balances
clicks, button presses, menus, text entry, sliders, scrolling, dragging, and
keyboard input. Discovery and control lookup follow the same focused window, so
a second window opened with ⌘N never supplies another window’s controls. Font
seeds cover both sides without queuing every installed family; mutations still
sample the full font registry. Existing campaigns adopt the same schedule when
resumed. Discovered actions record their accessibility paths, roles, and names
for replay. Generated custom specimens use one action that opens the editor,
sets the text, and applies it, so reduction cannot leave only part of the edit
and `--max-text-units` bounds the text that actually reaches the renderer. The
numeric fields, scroll areas, and controls that both inspectors repeat carry
accessibility identifiers such as `Font B Size field`, which discovery prefers
to a title or description, so those controls are told apart without their paths;
earlier traces still resolve by their recorded labels. Recorded Match checkbox
actions resolve to the corresponding Optimize buttons; new Match actions use
option-specific identifiers. Progress reports use `measured-ms` for the action
sequence and resulting UI work; `total-ms` also includes app startup, shutdown,
and coverage collection. The action count shows completed/attempted actions,
followed by `skips=N` when an execution skipped picks. Campaigns pause while the
screen is locked or the desktop session is otherwise unavailable, because a
locked session hides app windows from Accessibility, and resume as soon as the
desktop returns. When the workbench controls are unavailable, campaigns retry
with a delay that grows from five to 60 seconds. These retries do not advance
the campaign or enter its corpus; `availability.json` and its associated run
retain the latest availability failure. Crashes, hangs, and correctness failures
are still preserved during an outage. Use `FUZZ_ARGS='--seed 42 --duration 10m'`
for a bounded campaign. Before every execution, the driver requires 512 MiB free
on both the artifact and temporary volumes; change the threshold with
`--minimum-free-space-mib`. The campaign keeps `.profraw` and
`coverage.profdata` only for executions that add region or hit-count coverage.
It writes a compact representative report only when a finding kind and signature
first appears, while `finding-occurrences.json` records its count and first and
latest executions and times. The first resume of an older campaign builds this
index, removes repeat reports, and strips duplicated coverage sets from the
reports it retains. Replay or reduce a finding with `make fuzz-replay CASE=…` or
`make fuzz-minimize CASE=…`; `make fuzz-benchmark` remeasures the corpus in an
optimized build without coverage instrumentation and excludes failed or
incomplete executions from its timings. Benchmarking waits for quiescence after
every action. Use `make fuzz-benchmark CASE=…` for an outlier report, or
`CORPUS=…` for a directory of traces or reports.
`actionLatencyMedianMilliseconds` contains the median interaction latency for
each action; `actionMedianMilliseconds` retains the resolution-plus-dispatch
measurement. A coverage-instrumented replay can also wait between actions with
`FUZZ_ARGS='--wait-for-quiescence'`. Set `FUZZ_ARTIFACTS=…` to keep a separate
campaign or replay directory. The driver requires an active, unlocked desktop
session and macOS Accessibility and event-posting permission. On first use, the
driver stays open while you enable `.build/fuzz-driver/UIFuzzDriver.app` in
System Settings, then relaunches itself and continues automatically. Its stable
bundle identity keeps the permission valid across rebuilds.

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

`make benchmark-highlights` replays the checked-in 100,000 UTF-16-unit specimen
that exposed a slow Shape toggle, then toggles Shape, Spacing, and Frequency. It
runs seven fresh processes in the optimized build without coverage, prints the
median latency of each action, and writes
`.build/highlight-benchmark/benchmark.json`. Action timings include control
resolution and accessibility dispatch, excluding the trace's fixed pacing
delays. Set `HIGHLIGHT_RUNS=…` or `HIGHLIGHT_OUTPUT=…` to change repetitions or
retain a separate result. Set `HIGHLIGHT_APP=…` to test another revision's
FuzzBenchmark app with the same driver and input. The
[highlight benchmark notes](docs/highlight-benchmark.md) record the baseline and
viewport-scoped implementation results.

Before entering the campaign loop, the driver runs a self-test against fresh app
instances. It requires Command-2 to enter glyph mode, a real click on
`Glyph canvas` to return to text mode, and an editor submission to update the
reported UTF-16 text length. It also kills a dummy child process and requires
the liveness check to see the exit within 100 ms. Any failure stops the driver
before the corpus or campaign state changes; successful probe artifacts are
removed.

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
The detail still ends with `Visible accessibility elements:`, which now lists up
to 100 named elements of that tree in document order, hidden ones included,
instead of a sorted list from every window. Discovery reads more of the tree,
and `measured-ms` leaves out waits and skipped picks, so timings and those
listings are not comparable with reports from earlier campaigns.

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

`Sources/TypefaceCore` is a Swift package for font discovery, shaping,
measurements, calibrated edits, matching, and ranking. `Sources/TypefaceOff`
contains the macOS UI and in-memory comparison state. Tests use Swift Testing:
SwiftPM runs the core tests, and Xcode runs the native tests inside the app. The
test host runs with activation prohibited so it cannot steal desktop focus.
`make test-app` runs only the native suite, saves its result bundle in
`.build/TestResults.xcresult`, and prints assertion failures when tests fail. A
runtime warning, such as SwiftUI’s, fails the run. `make coverage` runs both
with instrumentation and reports coverage through `llvm-cov`, requiring 100%
line and region coverage for every engine, app, and reusable fuzzing-support
source file. Tests for Inter’s optional variable axes and character variants
require that font to be installed.

The app supports macOS 15, but Xcode 27 needs macOS 26.6, and Xcode 26.4 and
later need macOS 26.2, so macOS 15 runs at most Xcode 26.3. CI builds the test
bundles with Xcode 27 and runs them without rebuilding on macOS 15 and 26, using
the Xcode 26 those runners have; the main job builds and tests separately on
macOS 27. `make build-for-testing` packs the core and native test bundles into
`.build/portable-tests.tar`, and the Swift Testing runtime and overlays of the
Xcode that built them into `.build/portable-runtime.tar`. `make stage-support`,
run with Xcode 26.6, packs its XCTest support library and XCTestCore into
`.build/support.tar`. `make test-without-building RUNTIME=…` unpacks the bundles
and runs them with the active Xcode, saving results like `make test-app`;
`testing` also unpacks the Testing runtime, and `support` that and the staged
XCTest support. `make smoke-launch` starts the built app and fails if it exits
within 15 seconds, so an older macOS checks the binary itself. A run that
executes no tests fails. A push to `main` skips the macOS jobs when
`make ci-reuse` finds a branch run of the same tree, finished within the last
day, whose every job passed on GitHub-hosted runners.

`make review` renders native text, glyph, single-font, and character search
windows into `.build/review` for visual inspection and records glyph redraw
timings in `glyph-performance.json`. It requires an active macOS desktop
session.

`make benchmark-startup` launches the optimized, sandboxed app in fresh
processes with coverage disabled. It measures process launch through the first
drawn pair of specimens and through the displayed initial ranking and typography
previews. One warmup is reported separately, followed by seven measured
launches; set `STARTUP_RUNS=…` to change the count and `STARTUP_OUTPUT=…` to
retain a baseline. `.build/startup-benchmark.json` records every run, phase
timestamps, medians, 90th percentiles, OS, revision, and executable hash. It
requires an active desktop session and opens and closes its own app windows. OS
and font caches are not flushed, so this measures repeated launches, not the
first launch after a reboot. Startup probes are compiled only into the dedicated
benchmark configuration.

`make profile-startup` samples one launch of the same optimized app at one
millisecond intervals using macOS’s `sample` profiler. It attaches just after
process creation, records two seconds, and closes its own app. The call stacks
are saved to `.build/startup-profile.txt`, with phase timestamps in
`.build/startup-profile.txt.launch.log`; set `STARTUP_PROFILE=…` to retain a
profile. Use `make benchmark-startup` for timings without profiler overhead.

`make benchmark` runs an opt-in release benchmark and writes
`.build/similarity-benchmark/scores.json`, rendered specimens, and
`review.html`. It compares the existing glyph IoU, signed distance fields,
multiscale ink, SSIM, MS-SSIM, and the combined score at 14, 22, and 36 points.
Open the HTML locally for blind triplet judgments with ties; download judgments
and import multiple reviewers’ files to calculate individual and majority
agreement. Nothing is uploaded. The JSON records configurations, component
scores, corpus and score versions, OS, scale, runtime, and quick/refined fit
results. `character-search.json` records character search index and query
timings.

Swift 6 language mode, strict concurrency, warnings as errors, `swift-format`,
and the shared [right-answers](../right-answers/README.md) guidelines apply.
Formatting also covers documentation and configuration. CI runs the same Make
targets; GitHub Actions are pinned to release commit SHAs.

OpenType character variants expose the names, preview characters, and alternate
options supplied by the font. Other features use binary settings or Core Text’s
AAT selectors. Importing font files directly and multilingual specimen design
remain future work. The existing glyph difference strip still ranks isolated
grapheme clusters.

Family ranking and fitting use an **experimental visual heuristic**, without a
calibrated confidence percentage or a human-validated ranking claim. Four
equally weighted components compare glyph distance fields, glyph ink at three
blur scales, shaped text, and advance/bearing/vertical metrics. Rasterization
preserves point size, display scale, baseline, and origin; blank padding
contributes no similarity. A shared 128 MiB LRU cache reuses renderings,
including inert feature settings, while retaining variation axes in the cache
key. Family ranking defaults to one concurrent comparison per available CPU core
and publishes results as they finish; cache access remains synchronized.
`make benchmark` also records ranking times with one worker, four workers, and
the available core count in `ranking-timings.json`, checking that all produce
identical scores.

The versioned ranking corpus covers printable ASCII, selected Latin accents, and
feature/spacing diagnostics. Fitting adds all distinct current characters and up
to 128 deterministically sampled words. It validates coverage of the complete
current text before searching and never compares a fallback font. The search
uses categorical combinations or a bounded beam, multiple continuous starting
points, joint axis steps, and progressively smaller steps. It is budget-limited
and cannot guarantee a global optimum. See the
[research and evaluation rationale](docs/research/font-similarity.md).

## Reading samples

Samples use each side’s configured font size and the font’s natural line
spacing, with the original line breaks preserved and no added paragraph spacing.

The reading sample contains the complete body of public-domain chapter IX,
“Queen Alice,” from Lewis Carroll’s
[Through the Looking-Glass](https://www.gutenberg.org/files/12/12-h/12-h.htm#link2HCH0009),
with its italics and verse breaks preserved. The chapter heading and attribution
are omitted from the specimen. Emphasis uses the selected family’s italic face;
an unavailable italic style is labeled in the specimen.

## Character frequencies

Frequency weighting uses a table of how often each character appears in text,
bundled as `Sources/TypefaceCore/Resources/character-frequencies.tsv`. It mixes
[FineFreq](https://huggingface.co/datasets/lgi2p/finefreq)’s per-language
character counts from web text, each normalized separately, in proportion to the
total speakers of the 40 most-spoken languages in Ethnologue (36 of which
FineFreq covers), plus Greek, Hebrew, and Polish. Characters that FineFreq’s
Unicode normalization folded away, such as …, ½, and fullwidth CJK punctuation,
are estimated from the non-normalized
[Leipzig Corpora Collection](https://wortschatz.uni-leipzig.de).

A character that appears at least once per thousand characters counts fully.
Rarer characters are discounted by the square root of how much rarer they are,
down to one-tenth, and characters missing from the table get that minimum. The
tooltip shows frequencies below 0.001% as “below 0.001%”.
[docs/character-frequency.md](docs/character-frequency.md) records how the
languages and the formula were chosen, and [NOTICE](NOTICE) credits the data.

`make frequencies` downloads the pinned FineFreq and Leipzig data (about 800 MB,
cached in `.build/character-frequencies`) and regenerates the table
reproducibly.
