# Typeface/Off

A native macOS typeface comparison workbench built with SwiftUI, AppKit, and
Core Text. Compare installed fonts in reading samples, inspect individual
characters, and see where their shapes and spacing differ.

## Run

The app runs on macOS 15 or later, but building it requires Xcode 27 with Swift
6.4 or later. Install XcodeGen for the app build; development checks also use
Bun, Node.js, Lefthook, zizmor, ShellCheck, shfmt, and jq:

```sh
brew install xcodegen bun node lefthook zizmor shellcheck shfmt jq
make setup
make run
```

`make build` creates `.build/xcode/Build/Products/Debug/TypefaceOff.app`, signed
locally with an ad hoc identity. `make project` generates
`TypefaceOff.xcodeproj` for development in Xcode. `project.yml` owns the
project, app metadata, and sandbox entitlements; generated files are ignored.

The app uses installed fonts. It makes no network requests and has no
third-party runtime dependencies. Install additional fonts with Font Book, then
reopen the app to refresh its catalog.

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
- Choose a reading sample or edit your own text. Enter a size in the center
  toolbar and press Return to set both sides. **Mixed** indicates different
  sizes.
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
- **Match…** searches B’s current face for closer axes, typography, and
  tracking. Uncheck any setting to lock it; size changes are opt-in. A quick
  search uses up to three seconds or 256 evaluations; **Refine** resumes for up
  to 15 seconds or 2,048 additional evaluations. A started comparison can finish
  after the time budget. **Stop** retains the best verified preview. Cancel
  discards it, and Apply changes only B in one undoable edit, recalibrating
  appearance links. Only improvements verified on the full fitting corpus can be
  applied.
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
earlier traces still resolve by their recorded labels. Progress reports use
`measured-ms` for the action sequence and resulting UI work; `total-ms` also
includes app startup, shutdown, and coverage collection. The action count shows
completed/attempted actions, followed by `skips=N` when an execution skipped
picks. Campaigns pause while the screen is locked or the desktop session is
otherwise unavailable, because a locked session hides app windows from
Accessibility, and resume as soon as the desktop returns. When the workbench
controls are unavailable, campaigns retry with a delay that grows from five to
60 seconds. These retries do not advance the campaign or enter its corpus;
`availability.json` and its associated run retain the latest availability
failure. Crashes, hangs, and correctness failures are still preserved during an
outage. Use `FUZZ_ARGS='--seed 42 --duration 10m'` for a bounded campaign.
Before every execution, the driver requires 512 MiB free on both the artifact
and temporary volumes; change the threshold with `--minimum-free-space-mib`.
Replay or reduce a finding with `make fuzz-replay CASE=…` or
`make fuzz-minimize CASE=…`; `make fuzz-benchmark` remeasures the corpus in an
optimized build without coverage instrumentation and excludes failed or
incomplete executions from its timings. Set `FUZZ_ARTIFACTS=…` to keep a
separate campaign or replay directory. The driver requires an active, unlocked
desktop session and macOS Accessibility and event-posting permission. On first
use, the driver stays open while you enable
`.build/fuzz-driver/UIFuzzDriver.app` in System Settings, then relaunches itself
and continues automatically. Its stable bundle identity keeps the permission
valid across rebuilds.

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
`typefaceoff-fuzz`, shows the guest's window while you allow UIFuzzDriver in its
Accessibility settings, and runs a one-second campaign to confirm the driver
works. Campaign setup suppresses interactive CrashReporter dialogs in the guest;
diagnostic reports are still written and copied into crash findings. Guest
timings are comparable to this Mac's but are not interchangeable with them. A
headless guest's display boots at 1024x768 points, narrower than the workbench
window, so each campaign first switches it to 1920x1080 points, which fits the
window and every control.

`Sources/TypefaceCore` is a Swift package for font discovery, shaping,
measurements, calibrated edits, matching, and ranking. `Sources/TypefaceOff`
contains the macOS UI and in-memory comparison state. Tests use Swift Testing:
SwiftPM runs the core tests, and Xcode runs the native tests inside the app. The
test host runs with activation prohibited so it cannot steal desktop focus.
`make test-app` runs only the native suite, saves its result bundle in
`.build/TestResults.xcresult`, and prints assertion failures when tests fail. A
runtime warning, such as SwiftUI’s, fails the run. `make coverage` runs both
with instrumentation and reports coverage through `llvm-cov`, requiring 100%
line coverage for every engine, app, and reusable fuzzing-support source file.
Tests for Inter’s optional variable axes and character variants require that
font to be installed.

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
executes no tests fails.

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
