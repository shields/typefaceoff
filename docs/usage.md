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

# Comparing fonts

Choose a family and style in each font row above the comparison. Type to search
for a family, use ↑/↓ to highlight it, and press Return to select it. Escape
dismisses the picker. Choose **None** for B to inspect A alone. Selecting B’s
family again restores its settings.

Each window holds its own fonts and sample text until you close it. The app
labels missing fonts and characters. To add a font, install it with Font Book
and reopen the app.

Choose a reading sample from the toolbar or edit your own text. Switching views,
inspecting characters, or toggling highlights preserves your undo history.
Undoing a font edit keeps the current character in view.

## Adjust the fonts

- Appearance is linked initially. Size preserves the B/A ratio, and weight,
  tracking, and shared axes preserve their offsets, including after a range
  limit temporarily clamps a value. Turn off **Comparison → Link Appearance** to
  adjust sides separately. Typography settings always remain independent.
- **Leading** sets the distance between text baselines in points (1–288).
  **Auto**, on by default, uses the font’s natural line spacing and displays its
  computed value. Turn Auto off to edit the value; turn it on or reset leading
  to restore automatic spacing. Explicit leading stays fixed when size changes.
  Linked leading preserves the point difference between explicit values,
  including after a range limit clamps a value. If either side is Auto when
  linked, entering a value sets both sides to that value; resetting either side
  restores Auto to both.
- Enter a size in either font row and press Option-Return to set both sides to
  that value.
- Typography previews use examples that change with the selected font and
  feature. Some fonts’ ligatures apply to scripts other than Latin. Features
  without a verified example show **No preview available**.

## Inspect characters

- Click a character in the text or difference strip to inspect it. Arrow keys in
  the glyph view navigate the ranked characters. Click the glyph canvas at 100%
  to return to the text, or choose **Text** (⌘1).
- Click the inspected character’s name, or choose **Find Character** (⌘F), to
  search by name (“left arrow”), by the character itself, or by code point
  (U+2192). Use ↑/↓ to highlight a result and Return to inspect it, or Escape to
  dismiss the search.
- In glyph view, use the mouse wheel, pinch gesture, or zoom buttons to magnify
  the overlay from 100% to 800% without changing font settings. Zoom follows the
  pointer for wheel and pinch gestures. Drag or scroll with two fingers to pan
  when zoomed; click the percentage to reset to 100%. Zoom and pan stay fixed
  while navigating characters. Glyph outlines and their shared-ink intersection
  render as cached vectors; bitmap fonts use raster rendering.
- Both individual glyphs stand over the metrics table on the left, with the
  enlarged overlay on the right. The overlay shows A-only ink in red, B-only ink
  in blue, and shared ink in black. Baseline, x-height, and vertical advance
  guides remain visible. Shape aligns left ink edges; Spacing alone aligns
  advance origins. Glyph scale and baseline stay fixed while navigating a
  sample. Advance and side bearings show native font units and em, independent
  of specimen size and added tracking.
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
  [Character frequencies](character-frequency.md).

## Find and fit similar fonts

- In B’s font picker, switch **Name** to **Similarity** to rank installed
  families against A’s family. Both use the family’s regular face (normal width,
  weight nearest 400) with that instance’s axis settings, an optical size that
  follows A’s point size, default typography, and zero tracking. Lower distance
  means closer. Search filters the live results; pending and unsupported
  families remain selectable. Choosing a family carries B’s settings forward as
  usual, so its specimen can differ from the default settings used for ranking.
- **Match…** opens beneath the font rows and previews B on the canvas. Click
  **Optimize** beside a setting to search for its closest value while keeping
  every other preview setting fixed. Searches start only when clicked, and
  successive searches build on the preview. Each search uses up to 15 seconds or
  2,048 evaluations. A started comparison can finish after the time budget.
  **Stop** retains the best verified preview. Cancel discards it, and Apply
  changes only B in one undoable edit, recalibrating appearance links. Only
  improvements verified on the full fitting corpus can be applied.

Family ranking and fitting use an experimental measure of visual similarity. The
[development guide](development.md#font-similarity) describes the scoring method
and its limits.

## Compare language coverage

Open **Languages** (⌘3) to compare character coverage by language and script.
The minimum speaker count starts at 8.3 million. Set it to **All** and enable
**Show historical** to browse the complete catalog. **Use Checked as Specimen**
creates an editable character sheet from the checked categories in one undoable
step. See [language coverage](languages.md) for the inventory policy,
limitations, and data generation.

## Keyboard shortcuts

The **Edit** menu’s Find Character (⌘F) searches for a character to inspect. The
**View** menu switches among Text (⌘1), Glyph (⌘2) and Languages (⌘3), shows the
comparison inspector (⌃⌘I), and toggles Shape (⇧⌘1), Spacing (⇧⌘2) and Frequency
(⇧⌘F). The **Comparison** menu focuses Font A (⌥⌘1) or Font B (⌥⌘2) and offers
Match (⇧⌘M), Swap Fonts (⌥⌘S), and Edit Sample Text (⇧⌘E).

## Reading samples

Samples use each side’s configured size and leading. They preserve the original
line breaks and add no paragraph spacing.

The reading sample contains the complete body of public-domain chapter IX,
“Queen Alice,” from Lewis Carroll’s
[Through the Looking-Glass](https://www.gutenberg.org/files/12/12-h/12-h.htm#link2HCH0009),
with its italics and verse breaks preserved. The chapter heading and attribution
are omitted from the specimen. Emphasis uses the selected family’s italic face;
an unavailable italic style is labeled in the specimen.
