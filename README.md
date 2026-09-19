# Typeface/Off

A native macOS typeface comparison workbench built with SwiftUI, AppKit, and
Core Text. Compare installed fonts in reading samples, inspect individual
characters, and see where their shapes and spacing differ.

## Run

Requires macOS 15 or later and Xcode with Swift 6.3 or later. Install XcodeGen
for the app build; development checks also use Bun, uv, Lefthook, and zizmor:

```sh
brew install xcodegen bun node uv lefthook zizmor
make setup
make run
```

`make build` creates `.build/xcode/Build/Products/Debug/TypefaceOff.app`, signed
locally with an ad hoc identity. `make project` generates
`TypefaceOff.xcodeproj` for development in Xcode. `project.yml` owns the
project, document type, and sandbox entitlements; generated files are ignored.

The app uses installed fonts. It makes no network requests and has no
third-party runtime dependencies. Install additional fonts with Font Book, then
reopen the app to refresh its catalog.

## Use

- Search either inspector’s font selector for an installed family, then choose a
  style. Select **None** for B to inspect one font; reselecting that family
  restores its previous settings.
- Appearance is linked initially. Size preserves the B/A ratio, and weight,
  tracking, and shared axes preserve their offsets, including after a range
  limit temporarily clamps a value. Unlock either inspector to adjust sides
  separately. Typography settings always remain independent.
- Choose a reading sample or edit your own text. Enter a size in the center
  toolbar and press Return to set both sides. **Mixed** indicates different
  sizes.
- Click a character in the text or difference strip to inspect it. Arrow keys in
  the glyph view navigate the ranked characters. Type a grapheme in the
  character field and press Return to inspect any Unicode character.
- The overlay shows A-only ink in red, B-only ink in blue, and shared ink in
  black. Baseline and x-height guides remain visible. Shape aligns left ink
  edges; Spacing alone aligns advance origins. Glyph scale and baseline stay
  fixed while navigating a sample. Advance and side bearings show native font
  units and em, independent of specimen size and added tracking.
- **Shape** and **Spacing** independently control highlighting and ranking.
  Scores use actual configured font shapes and metrics, including axes and
  substitutions. Ranking runs away from the UI thread, and obsolete requests are
  cancelled.
- **Match…** previews changes to B’s numeric weight, measured x-height, and
  average sample tracking. Cancel leaves the comparison untouched; Apply is one
  undoable edit. Weight matching and geometric rankings are heuristics, not
  perceptual similarity models.
- Save and reopen `.typefaceoff` documents with the standard File menu.
  Documents contain settings and sample text, not font files. Missing fonts and
  glyphs are labeled rather than silently compared using fallback fonts.

## Develop

```sh
make build
make test
make coverage
make lint
make fmt
```

`Sources/TypefaceCore` is a Swift package for font discovery, shaping,
measurements, calibrated edits, matching, ranking, and versioned document data.
`Sources/TypefaceOff` contains the macOS UI and document integration. New tests
use Swift Testing; `make coverage` runs them with instrumentation and reports
core coverage through `llvm-cov`. Tests for Inter’s optional variable axes and
character variants require that font to be installed. The browser algorithm’s
original tests run alongside the native tests.

`make review` renders native text, glyph, and single-font windows into
`.build/review` for visual inspection. It requires an active macOS desktop
session.

Swift 6 language mode, strict concurrency, warnings as errors, `swift-format`,
and the shared [right-answers](../right-answers/README.md) guidelines apply.
Formatting also covers the browser reference, documentation, and configuration.
CI runs the same Make targets; GitHub Actions are pinned to release commit SHAs.

OpenType character variants expose the names, preview characters, and alternate
options supplied by the font. Other features use binary settings or Core Text’s
AAT selectors. Importing font files directly, multilingual specimen design, and
contextual run-level difference analysis remain future work. Comparisons rank
isolated grapheme clusters, so they do not measure kerning pairs or word rhythm.

## Design reference

The original interactive browser study is preserved in `mockups`:

```sh
make mockup
```

Open [the mockup](http://127.0.0.1:8765).
[Interaction guide and reference screenshots](mockups/README.md).

The reading samples are public-domain excerpts from Lewis Carroll’s
[Alice’s Adventures in Wonderland](https://www.gutenberg.org/files/11/11-h/11-h.htm#chap01)
and
[Through the Looking-Glass](https://www.gutenberg.org/files/12/12-h/12-h.htm#chap01).
