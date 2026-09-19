# Typeface/Off · interactive UX study

From the repository root:

```sh
make mockup
```

Open **http://127.0.0.1:8765**. Stop the server with Control-C. Use
`--port 8766` if needed. Python 3.14 and a desktop browser are sufficient; there
are no packages to install.

The mockup is designed for macOS at 1440 × 900 and 1280 × 800. Its two demo
pairs are Helvetica Neue / Arial and Inter / Atkinson Hyperlegible Next. The
server reads the installed font files in `/System/Library/Fonts` and
`~/Library/Fonts`; it doesn't copy fonts into the repository. Unavailable
optional fonts are disabled. It binds only to localhost.

## Try it

1. Appearance is **locked by default**. Editing either side updates the other:
   weight selects the corresponding available style or variable weight; point
   size, tracking, and shared axes move together. Use either padlock to unlock
   independent adjustments. OpenType features always remain independent.
2. Click a colored character or a character in the bottom strip to open its
   large glyph comparison. The center shows A-only ink in red, B-only ink in
   blue, and shared ink in black. Arrow keys step through the strip. Character
   labels show the code point and Unicode name, such as
   `U+0061 LATIN SMALL LETTER A`; graphemes with multiple code points list each
   component.
3. Glyph advances and both side bearings are always shown in **font units (u)
   and em**. Each font’s units/em scale is displayed. Baseline and x-height
   guides are always visible; Spacing adds advance-origin guides. Shape and
   Spacing highlighting are independent: either, both, or neither can be
   enabled.
4. Open **Match…**, select weight, x-height, or tracking, then apply the preview
   to B. Cancel leaves the comparison unchanged. The Undo toolbar action (or
   Command-Z outside a text field) restores a complete linked edit in one step.
5. Use the pair selector above the window to try variable fonts. Inter has many
   real character variants and stylistic sets; the demo weight suggestion maps
   400 in A to 380 in B.
6. Edit your own text, collapse either inspector, or swap the entire A/B
   configurations. Selecting **None** in the right font selector provides a
   single-font view; selecting the previous font restores its settings.

The shared lock preserves deliberate adjustments. After matching 400/380, moving
A to 500 moves B to 480. Point size preserves the B/A ratio; tracking and shared
axes preserve their offsets. Static weights choose the nearest available style,
and variable values respect each font's axis range. Calibration survives
temporary clamping at a range limit. Relocking, applying a match, swapping
fonts, and replacing a font establish a new calibration from the current pair.
Changing families preserves appearance values where the replacement font
supports them.

The fourth design pass places mode, sample, size, undo, swap, and match controls
above the center pane. The outer titlebar retains the sidebar toggles. The
redundant font-summary row, overlay legend, zoom dropdown, and guides checkbox
have been removed. Charcoal chrome, larger controls, colored characters, and
circle-arrow resets remain. Size is expressed directly in points throughout. The
toolbar follows linked size edits and displays “Mixed” when A and B have
different sizes; entering a toolbar value sets both fonts to that size. There is
no separate scale multiplier. The feature search, status footer, redundant font
captions, and separate remove-font control have been removed.

## What's real, and what's illustrative

Text, OpenType/Apple typography controls, variable axes, glyph masks,
supported-character detection, measured x-height, and spacing measurements use
the actual font data and browser shaping. AAT features with known tag
equivalents are exposed for Helvetica Neue. Required shaping features are listed
as automatic rather than editable. No synthetic weights or fallback glyphs are
intentionally substituted into the specimens.

Native-unit metrics measure the configured face at its unitsPerEm scale, without
specimen scaling or added tracking. They remain stable when the displayed point
size or tracking changes, but reflect selected font axes and glyph
substitutions. Fonts can have different coordinate scales: the default Helvetica
Neue a has an advance of 537 u at 1000 units/em; Arial's is 1139 u at 2048
units/em. These values were checked against the actual `hmtx` tables. Footer em
values divide the measured units by that face’s units/em, rounded to three
decimals: 537 u / 1000 = 0.537 em; 1139 u / 2048 ≈ 0.556 em. See the OpenType
[horizontal metrics](https://learn.microsoft.com/en-us/typography/opentype/spec/hmtx)
and
[font header](https://learn.microsoft.com/en-us/typography/opentype/spec/head)
specifications.

**Weight matching is a demonstration heuristic**, not a perceptual matching
algorithm. The static pair chooses the nearest available weight; the variable
example proposes 95% of A's axis value. x-height uses the rendered lowercase x
in native units/em to suggest a point size, and tracking estimates average
advance differences over the current sample. These demonstrate suggested-value
interactions, not a production normalization engine. Suggestions are bounded to
the controls' ranges. Settings live in memory and disappear on reload.

With Shape enabled, the overlay aligns glyphs at the baseline and left ink edge
without stretching them. Spacing alone uses the baseline and advance origin.
Both toggles retain ink alignment and show advance guides. With neither enabled,
the basic ink-aligned overlay and baseline/x-height guides remain, without text
highlights. The overlap uses SVG masks so typography settings also apply to the
overlay. Missing characters are labeled rather than compared against a silent
fallback.

Glyph navigation uses a fixed baseline and a shared display scale computed from
printable ASCII, the current sample, and reference accents/descenders. The
selected glyph does not affect the scale or baseline. Switching between `a`,
`g`, `@`, punctuation, and accented forms therefore preserves their actual
proportions and baseline position. Resizing the view or changing the font
configuration can recompute the display scale. Unicode names come from Python’s
bundled `unicodedata` database through the local server, including names for
characters missing from the selected fonts.

The reading sample contains the opening two paragraphs of Lewis Carroll’s
_Alice’s Adventures in Wonderland_, Chapter I, “Down the Rabbit-Hole.” The
poetry sample contains the first three stanzas of “Jabberwocky” from _Through
the Looking-Glass_. Both are public-domain texts, sourced from Project
Gutenberg:
[Alice’s Adventures in Wonderland](https://www.gutenberg.org/files/11/11-h/11-h.htm#chap01),
[Through the Looking-Glass](https://www.gutenberg.org/files/12/12-h/12-h.htm#chap01).
Attribution appears at the end of each specimen. Alphabet, numeral, and custom
samples remain available.

This is a browser UX prototype. Native SwiftUI/AppKit implementation, saveable
documents, font importing, multilingual specimen design, and perceptual ranking
and production weight matching are follow-up work.

## Difference ranking

The previous hand-picked list has been replaced with measurements of the
configured fonts. Candidates include all shared printable ASCII characters (`!`
through `~`), plus shared grapheme clusters from the current sample. This
includes `@` even when the sample does not. Missing characters and whitespace
are excluded. The strip scrolls through every candidate; tooltips expose the
actual scores.

- **Shape:** rasterize at a reference size of 192 pixels/em for A, preserving
  B’s relative point size. Align baselines and left ink edges. The score is
  `1 − sum(min(alphaA, alphaB)) / sum(max(alphaA, alphaB))`: the fraction of
  combined ink that does not overlap, including antialiasing. Zero means
  identical ink; one means no overlap. Both glyphs are reduced together only if
  their shared bitmap would exceed 512 pixels. Added tracking is excluded from
  shape.
- **Spacing:** take the mean absolute difference of advance width (including
  added tracking), left side bearing, and right side bearing, expressed in A’s
  em. These normalized scores allow comparison between fonts with different
  units/em; glyph detail metrics still show each font’s native units.
- **Both enabled:** sort by the average of shape and spacing percentile ranks,
  with equal treatment of tied scores. This gives the metrics equal influence
  without mixing percentages and em values. With neither enabled, the combined
  ranking remains available to inspect, with no colored text characters.
- **Text highlights:** color the eight highest-scoring characters actually
  present in the sample for each enabled metric, excluding zero scores. Both
  enabled uses their union. Ranking always reflects the current styles, axes,
  OpenType variants, relative sizes, and tracking. Uniform point-size changes do
  not alter scores.

Scores are cached and calculated in small cancellable batches so rapid
adjustments cannot display stale results. Identical configurations score zero.
Enabling Inter’s `cv11` changes the measured `a`; changing tracking affects only
spacing. In the default Helvetica Neue / Arial comparison, `@` ranks fifth for
shape, with approximately 79% non-overlapping ink.

This is a **geometric heuristic**, not a perceptual similarity model.
Baseline-relative position counts toward shape difference, so thin punctuation
at different vertical positions can rank highly. Rasterization introduces small
numerical differences. Comparisons use isolated grapheme clusters, so contextual
ligatures, kerning pairs, and word rhythm need a future run-level analysis.

## Review screens

| Screen                                                      | What to review                                                                        |
| ----------------------------------------------------------- | ------------------------------------------------------------------------------------- |
| [Text comparison](screenshots/01-text.png)                  | Charcoal chrome, synchronized point sizes, and independently selectable highlights.   |
| [Glyph comparison](screenshots/02-glyph.png)                | Fixed baseline, Unicode name, units/em metrics, and the red/blue/black overlap for @. |
| [Matching preview](screenshots/03-matching.png)             | Compact parameter selection and before/after values.                                  |
| [Variable fonts](screenshots/04-variable-fonts.png)         | Locked weight and optical-size controls with an adjusted comparison.                  |
| [Single font](screenshots/05-single-font.png)               | Expanded specimen with None selected for B.                                           |
| [Character variants](screenshots/06-character-variants.png) | Inter’s actual single-storey a, enabled through cv11 and reflected in the overlap.    |
| [Text at 1280 × 800](screenshots/07-text-1280.png)          | The more compact window layout.                                                       |
| [Glyph at 1280 × 800](screenshots/02-glyph-1280.png)        | Three glyph views at the smaller window size.                                         |

## Validation

Checked in Chromium at 1440 × 900 and 1280 × 800. Checks cover the default lock,
symmetric static/variable weight updates, independent editing after unlocking,
calibrated offsets and point-size ratios, recovery from clamped ranges, atomic
Undo, cancelled/applied matching, native-unit invariance, alternate-glyph
metrics, independent typography, and single-font selection/restoration. Earlier
interaction checks also cover switching modes, scroll restoration, swapped
configurations, collapsed inspectors, custom text escaping, missing glyphs, and
guides.

Default advances for Helvetica Neue and Arial agree with their font-table
values. Inter's cv11 changes the actual shaped glyph and its native advance.
Font parsing checks verified sfnt checksums, coverage, metrics, and axis ranges
for all 12 available demo faces. JavaScript syntax and Python compilation checks
pass.

The third pass also checks all four highlight combinations, true zero scores for
identical fonts, tracking-only spacing changes, feature-sensitive ranking, @
inclusion, cancellation of stale calculations, shared/Mixed toolbar sizes,
calibrated size edits, and keyboard focus after toggling highlights. The
algorithm’s math has six dependency-free tests:

```sh
node --test mockups/tests/differences.test.js
```

The fourth pass checks the center toolbar and outer sidebar toggles, removal of
redundant chrome, both Carroll samples, full Unicode names (including combining
sequences and supplementary characters), baseline/scale invariance across 11
varied glyphs, units-to-em conversions for both fonts, always-visible
metrics/guides, linked size edits, and single-font mode. All 18 browser checks
pass with no runtime errors; the smaller layout was also reviewed at 1280 × 800.
