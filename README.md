# Typeface/Off

A native macOS typeface comparison workbench built with SwiftUI, AppKit, and
Core Text. Compare installed fonts in reading samples, inspect individual
characters, and see where their shapes and spacing differ.

## Run

Requires macOS 15 or later and Xcode with Swift 6.3 or later. Install XcodeGen
for the app build; development checks also use Bun, Node.js, Lefthook, zizmor,
ShellCheck, shfmt, and jq:

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
  scripts outside the 40 most-spoken languages by measured difference alone. See
  [Character frequencies](#character-frequencies).
- **Match…** previews changes to B’s numeric weight, measured x-height, and
  average sample tracking. Cancel leaves the comparison untouched; Apply is one
  undoable edit. Weight matching and geometric rankings are heuristics, not
  perceptual similarity models.
- Browsing glyphs, switching views, and toggling highlights preserve Undo/Redo.
  Undoing a font edit keeps the current inspection in view.
- Launching the app opens a fresh comparison window. Each window is independent;
  settings and sample text stay in memory and are discarded when it closes.
  Missing fonts and glyphs are labeled rather than silently compared using
  fallback fonts.
- Typography previews use examples that change with the selected font and
  feature. Some fonts’ ligatures apply to scripts other than Latin. Features
  without a verified example show **No preview available**.

The **View** menu switches between Text (⌘1) and Glyph (⌘2), toggles the font
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
keyboard input. Font seeds cover both sides without queuing every installed
family; mutations still sample the full font registry. Existing campaigns adopt
the same schedule when resumed. Discovered actions record their accessibility
paths, roles, and labels for replay, including controls with duplicate labels.
Progress reports use `measured-ms` for the action sequence and resulting UI
work; `total-ms` also includes app startup, shutdown, and coverage collection.
The action count shows completed/attempted actions. Campaigns wait when their
desktop session or workbench controls are unavailable, retrying with a delay
that grows from five to 60 seconds. These retries do not advance the campaign or
enter its corpus; `availability.json` and its associated run retain the latest
availability failure. Returning to an interactive desktop resumes exploration.
Crashes, hangs, and correctness failures are still preserved during an outage.
Use `FUZZ_ARGS='--seed 42 --duration 10m'` for a bounded campaign. Replay or
reduce a finding with `make fuzz-replay CASE=…` or `make fuzz-minimize CASE=…`;
`make fuzz-benchmark` remeasures the corpus in an optimized build without
coverage instrumentation and excludes failed or incomplete executions from its
timings. Set `FUZZ_ARTIFACTS=…` to keep a separate campaign or replay directory.
The driver requires an active desktop session and macOS Accessibility and
event-posting permission. On first use, the driver stays open while you enable
`.build/fuzz-driver/UIFuzzDriver.app` in System Settings, then relaunches itself
and continues automatically. Its stable bundle identity keeps the permission
valid across rebuilds.

`Sources/TypefaceCore` is a Swift package for font discovery, shaping,
measurements, calibrated edits, matching, and ranking. `Sources/TypefaceOff`
contains the macOS UI and in-memory comparison state. Tests use Swift Testing:
SwiftPM runs the core tests, and Xcode runs the native tests inside the app.
`make test-app` runs only the native suite, saves its result bundle in
`.build/TestResults.xcresult`, and prints assertion failures when tests fail.
`make coverage` runs both with instrumentation and reports coverage through
`llvm-cov`, requiring 100% line coverage for every engine, app, and reusable
fuzzing-support source file. Tests for Inter’s optional variable axes and
character variants require that font to be installed.

`make review` renders native text, glyph, and single-font windows into
`.build/review` for visual inspection and records glyph redraw timings in
`glyph-performance.json`. It requires an active macOS desktop session.

Swift 6 language mode, strict concurrency, warnings as errors, `swift-format`,
and the shared [right-answers](../right-answers/README.md) guidelines apply.
Formatting also covers documentation and configuration. CI runs the same Make
targets; GitHub Actions are pinned to release commit SHAs.

OpenType character variants expose the names, preview characters, and alternate
options supplied by the font. Other features use binary settings or Core Text’s
AAT selectors. Importing font files directly, multilingual specimen design, and
contextual run-level difference analysis remain future work. Comparisons rank
isolated grapheme clusters, so they do not measure kerning pairs or word rhythm.

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
FineFreq covers). Characters that FineFreq’s Unicode normalization folded away,
such as …, ½, and fullwidth CJK punctuation, are estimated from the
non-normalized [Leipzig Corpora Collection](https://wortschatz.uni-leipzig.de).

A character that appears at least once per thousand characters counts fully.
Rarer characters are discounted by the square root of how much rarer they are,
down to one-tenth, and characters missing from the table get that minimum. The
tooltip shows frequencies below 0.001% as “below 0.001%”.
[docs/character-frequency.md](docs/character-frequency.md) records how the
languages and the formula were chosen, and [NOTICE](NOTICE) credits the data.

`make frequencies` downloads the pinned FineFreq and Leipzig data (about 800 MB,
cached in `.build/character-frequencies`) and regenerates the table
reproducibly.
