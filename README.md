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
inspectors (⌥⌘1 and ⌥⌘2), and toggles Shape and Spacing highlights (⇧⌘1 and
⇧⌘2). The **Comparison** menu offers Match (⇧⌘M), Swap Fonts (⌥⌘S), and Edit
Sample Text (⇧⌘E). Commands apply to the active comparison window and are
unavailable while its editing or matching sheet is open.

## Develop

```sh
make build
make test
make coverage
make lint
make fmt
```

`Sources/TypefaceCore` is a Swift package for font discovery, shaping,
measurements, calibrated edits, matching, and ranking. `Sources/TypefaceOff`
contains the macOS UI and in-memory comparison state. Tests use Swift Testing:
SwiftPM runs the core tests, and Xcode runs the native tests inside the app.
`make test-app` runs only the native suite, saves its result bundle in
`.build/TestResults.xcresult`, and prints assertion failures when tests fail.
`make coverage` runs both with instrumentation and reports coverage for both the
core and app through `llvm-cov`, requiring 100% line coverage for every source
file. Tests for Inter’s optional variable axes and character variants require
that font to be installed.

`make review` renders native text, glyph, and single-font windows into
`.build/review` for visual inspection and records glyph redraw timings in
`glyph-performance.json`. It requires an active macOS desktop session.

`make benchmark` runs an opt-in release benchmark and writes
`.build/similarity-benchmark/scores.json`, rendered specimens, and
`review.html`. It compares the existing glyph IoU, signed distance fields,
multiscale ink, SSIM, MS-SSIM, and the combined score at 14, 22, and 36 points.
Open the HTML locally for blind triplet judgments with ties; download judgments
and import multiple reviewers’ files to calculate individual and majority
agreement. Nothing is uploaded. The JSON records configurations, component
scores, corpus and score versions, OS, scale, runtime, and quick/refined fit
results.

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

The reading sample is the complete public-domain chapter IX, “Queen Alice,” from
Lewis Carroll’s
[Through the Looking-Glass](https://www.gutenberg.org/files/12/12-h/12-h.htm#link2HCH0009),
with its italics and verse breaks preserved. Emphasis uses the selected family’s
italic face; an unavailable italic style is labeled in the specimen.
