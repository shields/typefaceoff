# Typeface/Off: the redesign

This is the design the app is being rebuilt to, from a blank window. The owner
approved it on 15 November 2026; the rulings are under [Decisions](#decisions).

Mockups, each the whole 1440 x 900 window drawn in HTML and rendered at twice
that size, are in `mockups/`: `text.png`, `glyph.png`, `languages.png`,
`detail.png`, `match.png`, `none.png`, `missing.png` and `missing-font.png`.
They are drawings of the design, not the app. Where this document names a page
such as `glyph.html`, it means the page that `mockups/build.py` generates and
its render of the same name (see [Notes on the mockups](#notes-on-the-mockups)).
All measurements below are points in that window.

`research/` holds what the design rests on: `platform-api.md` and `hig.md`
(Apple's documentation and Human Interface Guidelines, read through the
`cupertino` index), `buildability.md` (how each structural idea is built and
what needs a prototype) and `capability-audit.md` (every capability of the app
before the rebuild, so that none is lost).

## The idea

The window is one sheet of paper headed by a two-line specification, A above B,
that is at once the title, the colour key, the font pickers and the settings;
one line of characters ranked by difference is its index, and everything below
is the comparison. Nothing flanks the canvas: the only pane is the system
inspector, closed until asked for.

It is the Two Lines frame from the judged round, with the header re-set as a
masthead, the index line rebuilt so its bars can be read, the guides drawn
neutral, Match drawn as a live mode, and the language sheet set on a fixed cell
grid.

## Structure

| Band                         | y                     | Contents                                                                       |
| ---------------------------- | --------------------- | ------------------------------------------------------------------------------ |
| Toolbar (system)             | 0-52                  | Sample pull-down, view switch, search field, inspector toggle                  |
| Specification                | 52-157                | Label row, row A, row B; closes with an ink rule at 157                        |
| Match band (Match mode only) | 150-233               | Inside the header, under row B; the ink rule moves to 233                      |
| Index line                   | 158-234               | Ranked characters; in Languages the filter line; closes with a hairline at 234 |
| Canvas                       | 235-900               | Text, Glyph or Languages                                                       |
| Inspector (system, optional) | x 1120-1440, y 52-900 | Facts, Appearance, Typography                                                  |

One ground: window and canvas are both rgb(251 252 253). There are no fills and
no panels; selection is marked in ink, never with a wash. Rules come in two
kinds: ink (the header's closing rule, the glyph baseline and the selection
marks) and hairline (everything else). Structural rules are inset 24; the
measure starts at 64.

### The grid

The body has two columns and the header is set on them.

|                            | Left column                           | Gutter | Right column                                |
| -------------------------- | ------------------------------------- | ------ | ------------------------------------------- |
| x at 1440                  | 64-688                                | 64     | 752-1376                                    |
| x at 1120 (inspector open) | 64-528                                | 64     | 592-1056                                    |
| Header                     | Letter, family, style                 |        | Size, Weight, Leading, Tracking, Typography |
| Text                       | A's column                            |        | B's column                                  |
| Glyph                      | Name, A alone, B alone, metrics table |        | "x-height", "baseline", the overlay         |
| Languages                  | The table                             |        | The selected language                       |

What a font is stands over the left column; how it is set stands over the right,
and about 300 of white separates the two (Style ends near x 444, Size starts at
752). The header's letters A and B hang at x 40, 24 left of the measure, and
every hanging A or B in the body sits at the same x 40, under the A of the
header, or 24 left of the right column. A selection tick hangs at the same x 40.

Header column positions at 1440: letter 40, family 64, style 384, Size 752,
Weight 840, Leading 912, Tracking 1016, Typography 1152; Match… ends at 1416. At
1120: family 64, style 320, Size 592, Weight 680, Leading 744, Tracking 840;
Match… ends at 1096. The header holds no facts about the fonts: Units/em and
x-height are in the Glyph table and the inspector.

### Toolbar

Four system items, each mirrored by a menu command. Nothing else belongs to the
window as a whole.

- **Sample** (leading): a pull-down titled with the current sample. It lists
  Queen Alice, Alphabet, Numerals & punctuation, the custom text or character
  sheet when there is one, a separator, and **Edit Text…** (⇧⌘E), which opens
  the existing sheet.
- **Text / Glyph / Languages** (centred, `.principal`): a segmented picker.
- **Search** (trailing): "Find Character" in Text and Glyph, "Search Languages"
  in Languages.
- **Inspector** toggle (trailing edge).

No Undo, Match or Swap in the toolbar. The inspector opens beneath the toolbar,
so the view switch and the search field stay where they are when it opens (the
judged Two Lines moved both).

### Specification

Three rows on the grid.

**Label row** (y 58-78, 11 pt, secondary ink). Swap and the link at its head,
then column heads and nothing else:

- **Swap** at x 34, a 20 x 20 button with vertical arrows, centred above the two
  letters it exchanges. Disabled without a second font.
- **Link A and B** at x 64, a checkbox. It links Size, Weight, Leading and
  Tracking (and shared axes); typography is never linked. Without a second font
  it is dimmed and keeps its stored state: a dimmed tick says the link is
  suspended, not lost.
- A label over each value column. While linked, a label carries the preserved
  relation when it is not the identity, in ink: `Size ×0.977`,
  `Tracking +0.004 em`, `Leading −1.000 pt`, `Weight +40`. A relation is
  computed, so it has three decimals; an axis offset is in the axis's own units
  (see Numbers). The relation is a pull-down with two items, **Make B Equal to
  A** and **Make A Equal to B**.

The colour key's words are not here; they stand in the index line, beside the
overlays they explain. The letters of the two rows below are the key's other
half.

**Row A** (baseline y 106) and **row B** (baseline y 142), 36 apart:

| Cell       | Set as                                                                                                                                                                                                    | Kind                                                                            |
| ---------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------- |
| Letter     | **A** or **B** in 13 pt bold, in the font's colour: A red, B blue. There is no square. Without a comparison (B None or not installed) B has nothing to key and its letter is secondary ink; A's stays red | The colour key                                                                  |
| Family     | 26 pt, in the font's own face and chosen style, then a chevron                                                                                                                                            | Button: opens the font picker                                                   |
| Style      | 13 pt, then up-down chevrons                                                                                                                                                                              | Pop-up button                                                                   |
| Size       | `22 pt`; `22.00 pt` over `21.46 pt` (see Numbers)                                                                                                                                                         | Editable number                                                                 |
| Weight     | `400`                                                                                                                                                                                                     | Read-only for a static font; an editable number when the font has a weight axis |
| Leading    | `26.616 auto` (the number underlined, in secondary ink) or `28 pt`                                                                                                                                        | Editable number; see below                                                      |
| Tracking   | `0 em`; `0.000 em` over `0.004 em`                                                                                                                                                                        | Editable number                                                                 |
| Typography | `Default`, `1 change`, `2 changes`, then a chevron                                                                                                                                                        | Button: opens the inspector at Typography                                       |
| **Match…** | Bordered button at the end of row B                                                                                                                                                                       | Enters Match mode                                                               |

Hierarchy: the names are 26 pt and the only large type in the chrome; values are
13 pt tabular; labels are 11 pt secondary. Nothing in the header is boxed at
rest except Match…; in Match mode the only boxes are Stop, Cancel and Apply.

**One affordance rule, visible at rest.**

- An underline means you can type here. The underline is `#8e939b` (3.0:1 on
  paper); the unit after the number is secondary ink and never underlined.
- Ink means an explicit value; secondary ink means a computed one. So `22 pt` is
  ink over an underline, automatic leading is secondary ink over an underline
  (`26.616 auto`), and a static weight is secondary ink with no underline: read
  from the font, and not a field.
- A word in ink followed by a chevron is a button or a menu: family, style,
  Typography, a relation.

Fields take a typed value and Return; ↑ and ↓ step (⇧ ten steps, ⌥ a tenth); Tab
moves along the row, then to the next row. The pointer is the I-beam over a
number. ⌥Return in a field sets the same value in both fonts whatever the link
says, which is what the old centre size field did.

A field's hit and focus rectangle is its whole cell, not its digits: from 6 left
of the column to 16 short of the next, 24 high (94 x 24 for Leading, 78 x 24 for
Size). On hover or focus the system focus ring is drawn round that rectangle and
a small stepper appears at its trailing end, so the arrow keys' stepping has a
visible, clickable counterpart. `missing.html` shows B's Leading focused.

**Leading.** Automatic leading shows the computed value in secondary ink,
underlined as every field is, with `auto` where the unit would be, always to
three decimals (`26.616`, `25.720`). Type a value and it becomes explicit
(`28 pt`, ink; `28.000 pt` while the other font's leading is automatic, so the
pair lines up); clear the field and it returns to automatic. The inspector has
the visible control, an Auto checkbox per font. Linked behaviour is the app's:
explicit values keep their point difference; if either side is automatic,
entering a value sets both sides to it, and resetting either side restores
automatic to both. The range (1-288) is in the field's help tag and at the ends
of the inspector's slider; an out-of-range entry is rejected, not silently
clamped.

**Names.** A name is set in its own face only when that face is installed and
can draw every character of its name; otherwise it is set in the system font. A
font that is not installed is named by its PostScript name in the system font,
in secondary ink, followed by a warning symbol and **Not installed** in ink
(`missing-font.html`). Nothing is ever drawn in a substitute.

### Index line

The ranked differences, directly under the specification in Text and Glyph (y
158-234).

- One cell per character on a 48 pitch, starting at x 64; 22 fit before the
  block at the right at 1440, 16 at 1120. Each character is a true overlay at 26
  pt, the size of the family names (A-only ink red, B-only ink blue, shared ink
  black), aligned as the Glyph overlay is, on one common baseline at y 200. It
  is set flush left: the two left ink edges stand at the cell's origin (64, 112,
  160 and so on), so the first character stands on the measure under the names.
- Under each character one bar, 2 pt, at y 211-213, starting at the cell's
  origin, on a hairline scale 44 long (4 short of the pitch, so neighbouring
  bars never touch). The bar is the score the line is ranked by, so the bars
  never grow from left to right and the order can be checked by eye. The scale
  is the largest measured value in the ranking. With Frequency on, the measured
  value lies under the bar as a track (`#8e939b`, 3.0:1), also 2 pt, and the ink
  is the weighted value; with Frequency off only ink shows.
- There is one bar whatever the criteria. With Shape alone it is Shape, with
  Spacing alone Spacing, and with both it is the app's combined score (the sum
  of the two percentile ranks). The two parts are in the character's help tag,
  not drawn: a split of percentile ranks is not a quantity worth reading by eye,
  and a second bar made the line the heaviest thing in the window.
- The inspected character is marked on the band's closing hairline: under its
  cell (x 64-112 for the first) the hairline thickens to a 2 pt ink rule, y
  233-235. No wash.
- The trailing edge fades over 72 pt; the line scrolls sideways, follows the
  inspected character, and a vertical wheel scrolls it when the pointer is over
  it.
- At the right end, a block standing on the last header column (x 1152 at 1440,
  x 840 at 1120) and ending at the margin (1416, 1096). First line, on baseline
  y 180: the caption **Differences** flush left and the colour key flush right:
  three words in 11 pt semibold, each in the ink it names, in the order of the
  layout, **Only A** in red, **Shared** in ink, **Only B** in blue. There are no
  swatches. Second line: three checkboxes spread over the block's width,
  **Shape**, **Spacing**, **Frequency**. After the Frequency label stands a 12
  pt sample of what it adds to a bar, ink over track; it is always shown, so the
  checkboxes do not move when Frequency is toggled, and its right end is on the
  margin. A small progress mark follows the caption while ranking runs.
- The key leaves with the block: there is none in Languages, with B None or with
  a font that is not installed, where no A-only or B-only ink is drawn.
- Click a character to inspect it; ← and → step along the line from the line or
  the canvas. The help tag gives the character's name, Shape, Spacing, frequency
  and weight, as today.
- In the line's place when there is no ranking: "No shared characters to
  compare." for a true empty ranking; "Choose a second font to compare." with B
  set to None (`none.html`); "B is not installed. Choose an installed font to
  compare." when B is not installed (`missing-font.html`).

### Text

Two columns of the sample, 624 wide with a 64 gutter and nothing between them
(`text.html`).

- A bold red **A** and a bold blue **B** hang at the first baseline, at x 40 and
  x 728. B's is secondary ink when B is not installed.
- The two first baselines are aligned at y 284, whatever the two leadings are;
  each column then runs in its own leading.
- The characters that differ most are red in A's column and blue in B's, as
  today. Click a character to inspect it. Whenever there is no ranking (B is
  None, B is not installed, or the ranking is empty) A's column is set wholly in
  ink, with no highlights: red would mean nothing.
- 22 pt Helvetica Neue sets about 58 characters to the line and 23 lines in
  view.

### Glyph

One composition on one baseline (`glyph.html`).

- **The baseline** is one ink rule at y 684 from the left window edge to the
  right. It is the only rule in the window that reaches both edges.
- **The overlay**, right, at 480 pt per em: A-only ink red, B-only ink blue,
  shared ink black. With Shape on the two left ink edges meet at x 840.
- **A alone and B alone**, left, at 240 pt per em in ink, side by side on the
  same baseline, A first. Their origins are x 196 and x 444.
- **Guides** are neutral hairlines. Vertical guides mark each font's origin and
  advance; the x-height guide runs from x 752 to the right window edge. Small
  bold **A** and **B** letters are pinned along the top of the stage (y 246)
  beside their guides: in a pair, the left guide's letter hangs to its left and
  the right guide's to its right, so two letters never touch. Guides within a
  pixel of each other merge into one, lettered `A B`. The letters are red and
  blue, and a merged guide's two letters keep one colour each. No red or blue
  line anywhere. Nothing else stands on the letters' line, so a letter can never
  be read as part of a control. A letter that would cross the 1416 margin hangs
  on the other side of its guide.
- **"x-height"**, **"baseline"** and the caption are the stage's three labels,
  all flush left at x 752: the first two just above their lines, the caption
  under the overlay. None of them moves when stepping between characters.
- **The character**, top left: code point at 11 pt (y 246), name at 20 pt
  regular on a 24 line (first baseline y 283), followed by a search symbol. The
  capitals carry the name; it is not semibold. A long name wraps within the left
  column (x 64-688) to at most two lines and is then truncated, with the whole
  name in the help tag. The pair is the visible button for Find Character.
- **Caption** under the overlay (x 752, baseline y 818), in the app's words: **A
  over B** Shape aligns left ink edges, or **A over B** Spacing alone aligns
  advance origins.
- **Zoom**, on the caption's baseline at the right: minus, the percentage, plus,
  each at least 20 x 20, the plus ending at the 1416 margin. Clicking the
  percentage resets to 100%. Zoom and pan act on the overlay's stage (x 752 to
  the window edge, y 235 to 900); the solos and the table do not move. Inside
  the stage the baseline pans with the overlay; left of the stage it stays put.
  The control and the caption are pinned and do not pan.
- **Metrics**: one table under the two solos, whose columns are the two figures
  (A at 196-356, B at 444-604), each with native units and em: Advance, LSB,
  RSB, then under a hairline x-height and Units/em. A's number is beside B's.
  Units are whole and em has three decimals (`800 u`, `0.800 em`); both are
  right-aligned, so the points of a column stand under one another.
- Scale and baseline are fixed while stepping between characters; they derive
  from the window and the fonts' vertical metrics, never from the glyph.
  Clicking the overlay at 100% returns to Text.

### Languages

The index line's slot holds one filter line with every filter visible
(`languages.html`): **Minimum speakers**, the logarithmic slider with its nine
tick labels (All to 920M), the value as an editable number (8.3M); then,
starting on the right column, a **Coverage** pop-up at x 752 (All, Both, A only,
B only, Neither) and **Show historical** at x 880; the count ("108 languages",
with a progress mark while coverage is checked) and **Clear Filters** at the
margin. The toolbar field searches languages. Choosing **Match…** here switches
to Text first, because Match previews on the canvas and Languages is locked
while it is open.

Left column, a sortable table: **Language**, **Speakers**, **A**, **B**. A row
gives the language's name only; its ISO code is in the detail.

- Speakers are whole millions, rounded to the nearest (`920M`, `77M`, `8M`),
  right-aligned. The table sorts by the exact count, so rows that show the same
  figure keep their true order, and the exact count is in the detail's facts
  line. A language under one million, which shows when the filter is lowered, is
  given in whole thousands (`250k`), and one under a thousand as its count
  (decision 16).
- Coverage is one mark per font: a filled dot for complete, a hollow dot for
  incomplete, a dash for a font that is not installed, a progress mark while
  checking. A note above the A and B columns names the two dots.
- The table's head shares its lines with the detail's head across the gutter:
  the note on the baseline of the language name (y 265), the column labels on
  the baseline of the facts line (y 289), and one closing hairline at y 304 for
  both columns.
- Rows are 28 high, the first at y 307; 21 are in view. The selected row is
  marked in ink: a 2 x 16 tick hanging at x 40, where A and B hang, and the name
  in semibold. No wash, no accent colour, no rule between rows.
- Sorted by speakers, largest first; click a heading to sort.
- Under the head, when it applies, the app's notices: "N matching languages are
  hidden by the speaker or historical filters." and "No languages match these
  filters."

Right column, the selected language:

- Its name at 20 pt semibold, with **Use Checked as Specimen** at the right. The
  button's name says what the checkboxes in the band headings are for.
- One facts line: `eng · 400,000,000 speakers (2006) · preliminary data`. It is
  code, autonym, speakers and the data's status; the autonym is left out when it
  only repeats the title above it, as for English, and stays when it differs
  (`deu · Deutsch · …` under German). At its right end the script,
  `Latin (Latn)`; a pop-up when the language has more than one orthography, with
  the app's suffixes (Historical, Required group).
- One band per category (Base, Auxiliary, Numerals, Punctuation, Currency)
  between hairlines. The heading is the checkbox (whether the category goes into
  the specimen), the name, and A's and B's counts (`A 56/56`, `B 56/56`).
- The body sets every character on a fixed grid of 22 x 22 cells, 28 to a row,
  17 pt, with A's row directly above B's and a hanging A and B. A character has
  the same address in both fonts. One that a font lacks is an empty dotted cell
  in place; the band's count drops (`B 43/44`) and the heading lists the missing
  characters at its right end as buttons that inspect them.
- The caveat, "Character coverage does not assess joining, mark placement, or
  visual quality.", and the **Sources and notes** disclosure. The dotted cell's
  key ("Missing") stands at the right of the caveat only when at least one band
  has an empty cell; English has none.
- Empty states are the app's: "Select a language to inspect its orthographies."
  and "This language's orthographies are hidden. Clear filters to see them."

### Inspector

The system inspector, 320 wide, opaque paper ground, a hairline divider, under
the toolbar (`detail.html`). Its content runs from x 1144 to x 1416, the 24
margin of the rest of the window. Numbers are entered in the specification; the
inspector is for exploring.

- **Facts**: Units/em, x-height and, for static fonts, Weight, with a column for
  A and one for B. x-height is given in em (`0.517 em`, `0.519 em`), so the pair
  can be compared without dividing; native units are in the Glyph table. Its
  closing hairline is at y 157, the same y as the header's ink rule.
- **Appearance**: the title, a **Reset** button that appears only when something
  in the section changed, and the same **Link A and B** checkbox. Then one block
  per setting: a label line with the relation and, only on a changed setting, a
  reset symbol; an A row and a B row, each with a slider, the number and its
  unit. The relation is the header's pull-down, chevron and both items included.
  Size (10-144) and Leading (1-288) are on logarithmic scales, as the speakers
  slider is, so the working sizes take the middle of the track; the number field
  is for fine values. Leading's rows end in an **Auto** checkbox per font; while
  Auto is on the number is secondary ink over its underline, the track has no
  filled part and the thumb is a hairline outline. Dragging that thumb turns
  Auto off, and the help tag says so. Variable axes follow, one block per axis
  in the union of the two fonts' axes; an axis only one font has shows one row.
- **Typography**: one table matched across both fonts. One row per feature with
  its OpenType tag, a checkbox column for A and one for B, a dash where a font
  lacks the feature. A feature with several values shows a pop-up on a line of
  its own for each font that has it. Groups (Common, Character variants,
  Stylistic sets, Numbers, Automatic shaping) are disclosure rows; Automatic
  shaping starts closed. A reset symbol appears only on a changed row, and the
  section's **Reset** only when something changed. The selected row is marked as
  a table row is: a 2 x 16 ink tick hanging 12 left of the content, and the name
  in semibold.
- **Previews.** The before → after preview is shown under the selected row and
  under every row whose setting differs between A and B; a feature only one font
  has counts as differing once it is off its default. Previews are 17 pt on a 22
  line, the size of the Languages cells. "No preview available" where the app
  has none.

In `detail.html` the fonts were unlinked, B was set to 21.5 pt and +0.004 em,
and they were linked again: the labels carry `×0.977` and `+0.004 em`, the sizes
read `22.0` and `21.5` and the trackings `0.000` and `0.004` in the header and
the inspector alike, Size and Tracking have reset symbols and Leading has none,
kerning is off in B, discretionary ligatures exist only in B and are on, and
Number Spacing exists only in A.

### Font picker

A popover hanging from the family name (`detail.html`):

- A search field, focused on opening.
- For B, a **Name / Similarity** switch; its last setting is remembered for the
  window.
- In Similarity: the app's caption "Similarity to Helvetica Neue · default
  settings", with the column head **Distance** on the same line, right-aligned
  over the figures (help tag "Lower is closer"); a 2 pt ink progress rule and
  "Compared 40 of 240" while ranking.
- **None** at the top for B. Each family set in its own face, a tick on the
  current one and the popover's highlight on the row the arrow keys are on (the
  only wash in the design, and the system's), the distance right-aligned. Rows
  not yet compared say Pending and unsupported ones Unavailable; both stay
  selectable. "No matching fonts" when the search finds nothing.
- ↑ and ↓ move the highlight, Return chooses, Escape dismisses; nothing changes
  until then.

### Match

**Match…** (⇧⌘M) puts the window into a live mode (`match.html`). No sheet.

- A band opens inside the header under row B (y 150-233), and the header's ink
  rule moves from 157 to 233. The index line and the canvas move down 76 and
  stay usable.
- The band has three baselines, shared by its two halves: 171, 194.5 and 218.
- **Optimize** stands under B's columns on the first baseline, flush on each
  column (752, 912, 1016, 1152): Size, Leading, Tracking; under Weight when B
  has a weight axis (a pull-down listing every axis when there are more); and
  under Typography a pull-down, **Optimize** with a chevron, listing B's
  features that are not automatic. They are ink words, not pills: an imperative
  in ink under a value, dimmed when disabled.
- Row B shows the proposal. A changed value is semibold; under its Optimize, on
  the second baseline, the band says what it was, in the column's decimals
  (`was 22.00 pt` under `21.46 pt`, with A's size reading `22.00 pt`). Computed
  values follow in regular weight (automatic leading 25.720 becomes 25.089 at
  21.46 pt), and they too say what they were (`was 25.720`), so no changed
  number is unmarked.
- The canvas is the preview: B's column, B's ink in the overlay and B's metrics
  are the proposal. The ranking stays that of the applied comparison. The band
  stays in view above the canvas, so the canvas itself carries no "preview"
  label.
- Left half of the band: **Match** and the app's line "Optimize one B setting at
  a time. Each search keeps your other preview settings.", whose B is bold blue;
  the status ("Comparing settings…", "Distance 0.203 → 0.187 · 412 evaluations",
  **Stop**, or "No better value found for this setting."); the app's caveat on
  one line (x 64-781), "Experimental visual heuristic using the current sample
  and Latin diagnostics. Lower distance is closer; this is not a confidence
  percentage." It clears Cancel (about x 1280 at 1440) at every content width
  down to the 960 minimum.
- **Cancel** (Escape) and **Apply** (Return) at the right, on the third
  baseline. Only **Stop**, **Cancel** and **Apply** are bordered. Apply is
  enabled only for a verified improvement, changes only B, and is one Undo step.
- While a search runs every Optimize is disabled and the one running reads
  Optimizing, with a progress mark after the word; **Apply is disabled**
  (outline, secondary text), so Stop and Cancel are the only actions and Return
  does nothing. When the search ends, by itself or by Stop, Apply is enabled and
  filled again if the preview holds a verified improvement.
- Locked while the band is open: the sample, Swap, the link, both pickers, every
  number (they lose their underlines, automatic leading included, which is the
  rule saying they cannot be edited), the inspector, Languages. Still usable:
  the index line, the arrow keys, Text and Glyph, zoom, Find Character.
- Without two installed fonts Match… is absent; the Comparison menu's command is
  disabled. In Languages the button switches to Text first.

### States

- **No comparison** (B is None or not installed): no A-only or B-only ink is
  drawn anywhere. B has nothing to key, so its letter is secondary ink, in the
  header and at its text column; A's letter stays red, as the font's name. Swap
  and the link are dimmed, the link keeping its tick; the Differences block, its
  key and Match… are absent; in Text, A's column is wholly ink.
- **B is None** (`none.html`): row B reads None in secondary ink and carries no
  values. Glyph shows A alone in ink at overlay scale with one table column;
  Text shows A's column in ink; Languages shows one coverage column and the
  Coverage pop-up offers All, Covered, Incomplete.
- **Missing glyph** (`missing.html`, U+0198, which Helvetica Neue lacks): the
  missing font's solo place reads "Character unavailable" in secondary ink, with
  no guides; its table cells are dashes; the overlay draws the other font's ink
  alone in that font's colour, with only its guides, and the caption says so.
  The character is not ranked, so no index cell is marked.
- **Font not installed** (`missing-font.html`): the row as described under
  Names; the font's column or figure is replaced by "This font is not installed.
  Choose an installed font above."; the index line gives the reason, "B is not
  installed. Choose an installed font to compare."; A's text has no highlights.
- **Empty ranking** (two installed fonts with no shared characters): the index
  line reads "No shared characters to compare." and both text columns are wholly
  ink.
- **Unlinked**: the checkbox is clear and the labels carry no relation
  (`missing.html`, which also shows a focused field).
- Errors are ink with a warning symbol. Red and blue never mean anything but the
  two inks and the letters that name their fonts.

## Type and colour

| Use                           | Size / line   | Weight                                         |
| ----------------------------- | ------------- | ---------------------------------------------- |
| Family names                  | 26 / 28       | The font's own                                 |
| Language name                 | 20 / 28       | Semibold                                       |
| Character name                | 20 / 24       | Regular, in capitals                           |
| Controls, values, table text  | 13 / 16 or 20 | Regular; semibold for titles; bold for A and B |
| Labels, captions, ticks, tags | 11 / 16       | Regular                                        |

Four chrome sizes and three weights; nothing under 11 pt. Chrome is the system
font; specimens are the compared fonts. Numerals are tabular (see Numbers).
Specimens share sizes too: the index characters are 26 pt, the size of the names
above them, and the Languages cells and the inspector's previews are both 17 pt.

| Token         | Value            | Contrast on paper | Use                                                                                           |
| ------------- | ---------------- | ----------------- | --------------------------------------------------------------------------------------------- |
| Paper         | rgb(251 252 253) |                   | Window and canvas                                                                             |
| Ink           | `#1b1c1f`        | 16.6              | Text, shared ink, ink rules, selection marks, checked controls, the index bars                |
| Secondary ink | `#5a5e66`        | 6.3               | Labels, units, computed values, B's letter when there is no comparison                        |
| Track         | `#8e939b`        | 3.0               | Measured-value track, field underlines, checkbox and slider outlines                          |
| Hairline      | `#c9ccd2`        | 1.6               | Structural rules, guides, bar scales, the track and thumb of an automatic slider (never data) |
| Wash          | Ink at 7%        |                   | The font picker's highlight only; selection elsewhere is an ink mark                          |
| A             | `#b43b43`        | 5.6               | Ink only in A, A's text highlights, the letter A, the key's **Only A**                        |
| B             | `#286b9d`        | 5.6               | Ink only in B, B's text highlights, the letter B, the key's **Only B**                        |

Hit targets are at least 20 x 20. Spacing is on a 4 pt unit: margin 24, measure
from 64, gutter 64, header rows 36, table rows 20 to 28, controls 24 high in the
content and 32 in the toolbar.

### The letters A and B

There are no key squares. The letter that labels a font is the key: **A** is
bold red and **B** is bold blue, and the key at the end of the index line is
three words in their own inks. Both colours are 5.6:1 on paper (5.7 on the white
of a popover), above the 4.5:1 that text needs, and a coloured letter or word is
never smaller than 11 pt nor lighter than semibold.

The colour runs throughout the window (decision 15). Every letter that labels a
font is in that font's colour:

- the header rows A and B and the letters hanging at the heads of the two text
  columns, 13 pt bold;
- the key's words, 11 pt semibold;
- in Glyph, the guide letters (11 pt bold) and the table's heads;
- in the inspector, the column heads of Facts and Typography, the row letters of
  the settings, the value pop-ups and the previews;
- in Languages, the table heads, the counts (`A 56/56`) and the hanging letters
  of the character grid;
- in the Match band, the B of "Optimize one B setting at a time." (11 pt bold).

The letter of a font that is None or not installed is secondary ink, and A's
stays red when B is absent. A letter inside a control's title, a caption, a
message or a command (**Link A and B**, **A over B**, "B is not installed.",
**Make B Equal to A**) is text and takes the colour and weight of the words
around it; the Match band's line is the one exception, because its B is the
band's only pointer to the row it acts on.

### Numbers

One rule wherever a number appears: the header, the inspector, the Glyph table,
the Match band and its "was", the relation labels and the picker's distances.

- **Measured or computed values always show three decimals.** Automatic leading
  (`26.616`, `25.720`); advance, side bearings and x-height in em (`0.800 em`,
  `1.015 em`, `0.042 em`, `0.517 em`); similarity and Match distances (`0.203`);
  relations (`×0.977`, `+0.004 em`, `−1.000 pt`).
- **Values in font units are whole numbers** (`800 u`, Units/em `2048`), as are
  a static font's weight, counts and percentages.
- **Values the user types** (size, explicit leading, tracking, a variable axis)
  show as many decimals as the more precise of A and B needs, at most three, and
  the same on both sides: `22` and `22`, `22.0` and `21.5`, `22.00` and `21.46`,
  `0.000` and `0.004`. Automatic leading counts as three, so an explicit leading
  beside an automatic one reads `28.000 pt` (`missing.html`). In Match, "was"
  takes its column's decimals. With one font, A shows what A needs. An axis
  relation follows the axis's values (`Weight +40`). This part is the owner's to
  decide (decision 14).
- **A and B align on the decimal point in every column.** Figures are tabular
  and a pair has the same decimals, so right-alignment does it. In a header
  column the two numbers are right-aligned in a box as wide as the wider of
  them, which stands flush left on the column, so `9.50` sits under the last
  four figures of `22.00`; the unit follows the number. The inspector's fields,
  the Glyph table, the Speakers column and the picker's distances are
  right-aligned columns.
- A field shows what is typed while it has the insertion point; the rule is
  applied on commit.

## Where each capability lives

| Capability (README "Use")                                                                      | Where                                                                            | Control                                                                                                       |
| ---------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------- |
| Search and choose a family; ↑/↓, Return, Escape; nothing changes until confirmed               | Family name in the specification                                                 | Popover: search field, list                                                                                   |
| Choose a style                                                                                 | Specification                                                                    | Pop-up button                                                                                                 |
| None in B; reselecting restores its settings                                                   | B's picker, first row                                                            | List row                                                                                                      |
| Linked appearance; ratio and offsets preserved through a clamp                                 | Label row; inspector                                                             | Link A and B checkbox; the relation written on each label                                                     |
| Unlink to adjust sides separately                                                              | Label row; inspector; Comparison > Link Appearance                               | Checkbox                                                                                                      |
| Size, tracking                                                                                 | Specification rows; inspector                                                    | Editable numbers; sliders                                                                                     |
| Weight and other axes                                                                          | Weight in the specification; every axis in the inspector                         | Editable number; sliders                                                                                      |
| Leading 1-288, Auto, computed value shown                                                      | Specification (clear the field for Auto); inspector                              | Editable number; slider and an Auto checkbox per font                                                         |
| Reset leading to Auto; linked Auto rules                                                       | Inspector label line; clearing the field                                         | Reset symbol on a changed row                                                                                 |
| Reset a setting; reset a section                                                               | Inspector; Comparison > Reset Appearance, Reset Typography                       | Reset symbol on changed rows; section Reset when changed                                                      |
| Set both sizes at once; "Mixed"                                                                | Either Size field; the relation on the Size label; Comparison > Make Sizes Equal | ⌥Return; pull-down; command. Both sizes are always on screen, so Mixed has nothing to hide                    |
| Typography features, previews, tags, "No preview available"                                    | Inspector, Typography                                                            | Checkbox per font; pop-ups; previews on selected and differing rows                                           |
| How many typography settings changed                                                           | Specification, Typography column                                                 | Button, opens the inspector at Typography                                                                     |
| Choose a sample; edit your own text                                                            | Toolbar, leading edge                                                            | Pull-down; sheet (⇧⌘E)                                                                                        |
| Languages (⌘3); speaker filter from 8.3M; All; Show historical; coverage filter; Clear Filters | View switch; filter line                                                         | Segmented picker; slider, number, pop-up, checkbox, button                                                    |
| Language rows: name, speakers, coverage per font; the code                                     | Languages table; the detail's facts line                                         | Table, sortable; text                                                                                         |
| Orthography, per-category coverage, character sheet, missing characters                        | Languages detail                                                                 | Script pop-up; category bands on the cell grid; missing characters as buttons                                 |
| Use as specimen (one Undo step)                                                                | Languages detail                                                                 | Button, **Use Checked as Specimen**                                                                           |
| Sources and notes; caveat                                                                      | Languages detail                                                                 | Disclosure; text                                                                                              |
| Click a character to inspect it                                                                | Text columns; index line                                                         | Click                                                                                                         |
| Arrow keys step through the ranked characters                                                  | Index line; Glyph                                                                | ← → ; View > Previous Character, Next Character                                                               |
| Type a grapheme and press Return to inspect any Unicode character                              | Toolbar search                                                                   | A query of exactly one grapheme (several code points allowed) inspects that grapheme on Return, ranked or not |
| Find Character (⌘F): by name, the character, or a code point                                   | Toolbar search; the character's name in Glyph                                    | Search field with a result list; ↑/↓, Return, Escape                                                          |
| Return to Text                                                                                 | Click the overlay at 100%; ⌘1                                                    | Click; view switch                                                                                            |
| Zoom 100-800% at the pointer; pan; reset                                                       | Glyph stage; zoom control; View menu                                             | Wheel, pinch, drag; minus, percentage, plus; ⌘+ ⌘- ⌘0                                                         |
| Zoom and pan fixed while stepping                                                              | Glyph                                                                            | Unchanged                                                                                                     |
| Overlay colours                                                                                | Glyph; index line; the key at the end of the index line                          | Drawing; key                                                                                                  |
| Baseline, x-height and advance guides                                                          | Glyph                                                                            | Neutral hairlines with A and B letters                                                                        |
| Shape aligns ink edges; Spacing alone aligns origins                                           | Glyph caption                                                                    | Text                                                                                                          |
| Advance and bearings in units and em                                                           | Glyph metrics table                                                              | Table                                                                                                         |
| x-height and Units/em per font                                                                 | Glyph table (units and em); inspector facts (em)                                 | Read-only values                                                                                              |
| Shape, Spacing                                                                                 | End of the index line; ⇧⌘1, ⇧⌘2                                                  | Checkboxes                                                                                                    |
| Frequency; weighted bar over a measured track; tooltip                                         | End of the index line (⇧⌘F); index cells                                         | Checkbox with a sample of the mark; bars; help tag                                                            |
| Ranking off the UI thread, with progress                                                       | Index line caption                                                               | Progress mark                                                                                                 |
| Similarity ranking in B's picker                                                               | B's picker                                                                       | Segmented switch; a Distance column; progress rule and count                                                  |
| Match…: Optimize per setting and per feature, Stop, Cancel, Apply                              | Row B; the Match band                                                            | Button; band                                                                                                  |
| Swap Fonts (⌥⌘S)                                                                               | Above the letters A and B                                                        | Button                                                                                                        |
| Undo and Redo; browsing preserves them                                                         | Edit menu                                                                        | ⌘Z, ⇧⌘Z                                                                                                       |
| Independent windows; the title names the fonts                                                 | Unchanged; title "Helvetica Neue vs. Arial" in the Window menu only              |                                                                                                               |
| Missing fonts and glyphs labelled, never substituted                                           | Specification row; canvas; table                                                 | Text and symbols                                                                                              |

### The items the audit listed for Two Lines

| Audit item                                           | Answer                                                                                                                                                                                                                                    |
| ---------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Leading Auto was an empty field with a placeholder   | Auto shows its value with the word `auto`; the inspector has an Auto checkbox per font, so A automatic with B explicit can be said; the range is stated; bad input is rejected                                                            |
| Setting both sizes at once                           | ⌥Return in a Size field; Make B Equal to A and Make A Equal to B on the relation; Comparison > Make Sizes Equal                                                                                                                           |
| Section resets only in menus                         | A Reset button in each inspector section, shown when the section changed, plus the two menu commands                                                                                                                                      |
| Feature optimisation in Match                        | The Optimize pull-down under Typography lists B's features; its result shows in B's Typography cell with what it was beneath                                                                                                              |
| Match under narrow widths or with the inspector open | Size, Weight, Leading and Tracking never leave the header, so their Optimize buttons always have a column; the feature pull-down takes the place Match… had on row B when Typography is not shown; the inspector is locked while matching |
| Many variable axes                                   | Only Weight is a header column. Every other axis is an inspector block. When any of them is off its default the Weight cell adds `+2 axes`, a button that opens the inspector at Appearance                                               |
| Typography took two steps                            | Still two with the inspector closed (the Typography cell opens it at the section); one while it is open. The inspector's state is kept per window                                                                                         |
| Previews only on the selected row                    | Also on every row where A and B differ                                                                                                                                                                                                    |
| Find Character and a typed grapheme                  | One rule, in the table above                                                                                                                                                                                                              |
| ⌘F in Languages                                      | Focuses the same field, which then searches languages; Edit > Find is titled to match                                                                                                                                                     |
| Hidden-orthography notice, empty states              | Kept in the app's words, under Languages and Index line above                                                                                                                                                                             |
| Swap when B is None                                  | Disabled                                                                                                                                                                                                                                  |
| Toolbar Undo button removed                          | Kept out; Edit menu only (owner decision 6)                                                                                                                                                                                               |

## Narrow widths

Content width is the window less the inspector. Minimum content 960 x 600;
opening the inspector in a window narrower than 1280 widens the window.

| Content width                     | What changes                                                                                                                                                                                                                                                                                                                                |
| --------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 1240 and up                       | Everything as drawn at 1440. The text columns and the family column take the extra width                                                                                                                                                                                                                                                    |
| Under 1240, or the inspector open | The header's columns close up to the 1120 positions. The Typography cell stays unless the inspector is open, which shows the same thing. The Differences block then stands on Tracking (x 840 at 1120)                                                                                                                                      |
| Under 1000                        | The Typography cell leaves. Family, style, Size, Weight, Leading, Tracking and Match… remain at every width                                                                                                                                                                                                                                 |
| Any                               | The family name truncates in the middle when it is longer than its column (304 at 1440, 240 at 1120)                                                                                                                                                                                                                                        |
| Any                               | The index line shows as many cells as fit before its block: 22 at 1440, 16 at 1120, 12 at 960. The block keeps its left edge on the last header column and its right edge on the margin                                                                                                                                                     |
| Any                               | Text columns are (content − 192) / 2 each; the gutter stays 64                                                                                                                                                                                                                                                                              |
| Glyph                             | The overlay keeps 480 pt per em while the height allows and the stage is at least 520 wide (content 1076), so opening the inspector at 1440 does not change it. The left block gives way first: under 1320 the solos stand at one-third of the overlay's scale and the table closes up to 452. Below 1076 the overlay scales with the stage |
| Languages                         | The table keeps 624 down to 1240, then narrows to 464; the cell grid drops whole columns (28, then 20 to a row), the same in both fonts                                                                                                                                                                                                     |

## Menus and keys

| Menu       | Commands                                                                                                                                                                                               |
| ---------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Edit       | Undo ⌘Z, Redo ⇧⌘Z, Find Character ⌘F (Search Languages in Languages)                                                                                                                                   |
| View       | Text ⌘1, Glyph ⌘2, Languages ⌘3; Show Inspector ⌃⌘I; Shape ⇧⌘1, Spacing ⇧⌘2, Frequency ⇧⌘F; Zoom In ⌘+, Zoom Out ⌘-, Actual Size ⌘0; Previous Character, Next Character                                |
| Comparison | Font A ⌥⌘1 and Font B ⌥⌘2 (focus that row's family; Return opens the picker); Swap Fonts ⌥⌘S; Link Appearance; Make Sizes Equal; Reset Appearance; Reset Typography; Match… ⇧⌘M; Edit Sample Text… ⇧⌘E |

In the window: ← → step characters; ↑ ↓ in a number step it (⇧ x10, ⌥ ÷10);
Return commits and ⌥Return commits to both fonts; Tab runs toolbar, label row,
row A, row B, index line (one stop, arrows inside), canvas, inspector; Escape
leaves a field, a popover or Match; Return applies Match.

⌃⌘I is what `InspectorCommands` supplies. ⌥⌘1 and ⌥⌘2 keep their keys and change
meaning from "toggle an inspector" to "go to that font".

## Accessibility

- **Colour is never alone.** The key names the three inks in words, beside the
  index overlays, and a coloured letter is still the letter. Every figure,
  column, row and guide carries a letter. Coverage marks differ in form (filled,
  hollow, dash).
- **Differentiate Without Color** (`accessibilityDifferentiateWithoutColor`):
  highlighted characters in the text gain an underline; in the overlay and the
  index cells A-only ink is hatched rising and B-only ink falling. A word cannot
  show a hatch, so with this setting on **Only A** and **Only B** in the key are
  each preceded by a 9 pt square in that hatch; this is the one place a key
  square returns.
- **Increase Contrast**: A becomes `#8f2530` (8.3:1) and B `#1a527d` (8.0:1);
  secondary ink `#3f4248`; hairlines take the track colour and tracks take
  secondary ink; field underlines become ink.
- **VoiceOver.** A bare number is a text field with a full label and value:
  "Font A size, 22 points"; "Font B leading, automatic, 25.720 points". A
  relation reads "B is 0.977 times A". Family names are buttons: "Font B family,
  Arial". The Typography cell reads "Font B typography, 2 changes, opens the
  inspector". Index characters are buttons in one group, "Differences", each
  with its name, rank and scores and the selected trait: "Inspect U+0040
  COMMERCIAL AT, 1 of 99". Coverage dots read "Complete" or "Incomplete". Each
  category sheet is one element that summarises ("Base, B, 56 of 56 present"),
  with the missing characters as separate buttons. The overlay's label is the
  app's: name, then "Font A in red, font B in blue, shared ink in black."
- **Keyboard.** Every control is a system control or a button and is reachable
  by Tab with Full Keyboard Access; the focus ring keeps the system's shape.
  Nothing depends on hovering: the underline, the chevrons and the checkboxes
  are all visible at rest, and a field's stepper, which hover shows, also comes
  with keyboard focus.
- **Reduce Motion**: the Match band and the inspector open without animation.
- Light only is a decision (owner decision 1); Increase Contrast and Reduce
  Transparency are still honoured.

## What the system supplies

|                       | macOS 15                                                                                                                                                                                                  | macOS 26 and 27                                                                                                                                                                                                                        |
| --------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Toolbar               | `toolbar` with `ToolbarItem(placement: .navigation)`, `.principal` and trailing items; standard bezel-free items; `Picker` with `.segmented`                                                              | The same items as glass capsules. `ToolbarSpacer(.fixed)` (26) would separate search from the inspector toggle; not required. `TabsPickerStyle` (27 beta) is the documented look for a view switch; not adopted while the target is 15 |
| Title                 | `navigationTitle` for the Window menu; `toolbar(removing: .title)` (14)                                                                                                                                   | The same                                                                                                                                                                                                                               |
| Search                | `searchable(text:placement:prompt:)` with `searchFocused(_:)` (15) and `searchSuggestions`; unverified in a window with no navigation container, so the fallback is an `NSSearchField` in a `ToolbarItem` | `DefaultToolbarItem(kind: .search)` (26) can place it; the field may collapse to a button when the toolbar is short                                                                                                                    |
| Paper to the top edge | `containerBackground(_:for: .window)` (15) and `toolbarBackgroundVisibility(.hidden, for: .windowToolbar)` (15)                                                                                           | Toolbar is clear by default; `scrollEdgeEffectStyle(_:for:)` (26) is left automatic                                                                                                                                                    |
| Light only            | `preferredColorScheme(.light)` on the window and on every popover and sheet; `NSApplication.appearance` for menus                                                                                         | The same                                                                                                                                                                                                                               |
| Inspector             | `inspector(isPresented:content:)` (14), `inspectorColumnWidth(min:ideal:max:)`, `InspectorCommands` (⌃⌘I); a toolbar button bound to the flag. Trailing column with a divider                             | The same call; the pane floats as glass, so it is given an opaque paper background. Placing it under the toolbar depends on where the modifier sits in the hierarchy: unverified                                                       |
| Neutral controls      | `tint(_:)` set to ink for checkboxes, sliders and buttons                                                                                                                                                 | The same; the focus ring and AppKit selection do not follow `tint` (hard problem 1)                                                                                                                                                    |
| Numbers in the header | `TextField(_:value:format:prompt:)` with `.textFieldStyle(.plain)` and a drawn underline; `pointerStyle(_:)` (15)                                                                                         | The same; content-layer controls get no glass                                                                                                                                                                                          |
| Pop-ups, checkboxes   | `Picker` with `.menu` and `menuStyle(.borderlessButton)`; `Toggle` with `.checkbox`                                                                                                                       | New shapes, same calls                                                                                                                                                                                                                 |
| Sliders               | `Slider`                                                                                                                                                                                                  | Glass knob while dragging; `SliderTick` (26) could draw the speaker ticks; on 27 beta `Slider` is no longer an `NSSlider` (hard problem 9)                                                                                             |
| Font picker           | `popover(isPresented:attachmentAnchor:arrowEdge:)`                                                                                                                                                        | Glass popover, pinned light                                                                                                                                                                                                            |
| Languages table       | `Table` with selection and sort order                                                                                                                                                                     | The same                                                                                                                                                                                                                               |
| Glyph stage           | `NSScrollView` with `allowsMagnification` (existing)                                                                                                                                                      | The same                                                                                                                                                                                                                               |
| Arrow keys            | `onKeyPress(_:action:)` (14) on a `focusable` index line                                                                                                                                                  | The same                                                                                                                                                                                                                               |
| Glass in the content  | None                                                                                                                                                                                                      | None: the header, index line and canvas are the app's drawing on paper and look the same on all three systems                                                                                                                          |

No API newer than macOS 15 is required, so gated source files need no
`#available` branch.

## Hard problems, and what each needs

1. **Neutral selection and focus.** `tint` does not reach the focus ring,
   `Table` selection or `NSTextView` selection, and a user whose accent is red
   or blue would see that colour in the chrome. Answer: draw selection
   ourselves, as an ink mark in the index line, the Languages table and the
   inspector and as a neutral wash in the picker; for the Languages table
   prototype two routes, a `Table` with a cleared row background plus our own,
   and an `NSTableView` wrapper with a custom row view; set the text view's
   selection attributes and insertion point. Test with the accent set to red and
   to blue on 15, 26 and 27. If the focus ring cannot be made neutral, keep the
   system ring: it is transient.
2. **Paper under the title bar and the glass toolbar.** Prototype the bare
   window on 15 and 26, with Reduce Transparency and Increase Contrast, on a
   dark desktop. The fallback on 15 is a toolbar background set to paper.
3. **Toolbar.** Check that `.principal` centres on the window when the two sides
   are unequal (if not, accept the system's centring), and prototype Find
   Character in the toolbar field: the result rows need a glyph in each font and
   a "not in font" state. If `searchSuggestions` cannot hold such rows, the
   results open as the existing popover anchored under the field.
4. **Inspector under the toolbar, and its hidden state.** Verify the placement
   that keeps the toolbar from reflowing; if the pane must be full height, pin
   the view switch to the window's centre another way or accept the shift.
   Assume hidden inspector content loses view-local state: disclosure and scroll
   state go into the window's model.
5. **The header's fields.** Bare text fields with steppers by key, a stepper
   control and focus ring on the whole cell on hover and focus, ⌥Return, link
   propagation and fail-fast validation. Build one `SpecificationField` and test
   it in the package before laying out the header. The fuzzer needs distinct
   identifiers for the header's copy and the inspector's (`Font A Size field`
   beside the existing `Font A Size`).
6. **Names in their own face.** `Font.custom` substitutes silently. Branch on
   `FontRenderer.isAvailable` and on whether the face covers its own name; test
   with a symbol font and a font with no Latin.
7. **Index line.** Left-ink alignment and a common baseline come from the app's
   own drawing, not from `Text`. Prototype wheel scrolling of a horizontal
   `ScrollView`; the fallback is an `NSScrollView` bridge that maps a vertical
   wheel to horizontal scrolling. The cells stay buttons with today's labels, so
   tests and traces survive.
8. **One baseline across the window.** The left figures and the table are fixed;
   the stage is the existing magnifying scroll view from x 752. Draw the rule in
   two pieces from one published baseline y, 1 px at every magnification, and
   publish guide positions from the same geometry function so the pinned letters
   can be laid out outside the magnified view. Units-per-em normalisation and
   the fixed scale get tests in the package.
9. **Sliders and resets.** Two sliders per setting always (A and B), so no
   joined control and no state-dependent identifiers. Reset symbols and section
   Resets that appear only when needed are absent controls, not disabled ones:
   reserve their width, and teach the fuzzer's resolution rules that absence is
   a skip, or regenerate the corpus. Check the slider's accessibility role
   on 27.
10. **Typography as one table.** A model that unites the two fonts' features by
    identifier, with a row holding A's feature, B's feature, or one of them.
    Decide and test what unites an AAT feature with an OpenType one (Common
    Ligatures and `liga` are separate rows in the mockup, which is the safe
    answer). Previews are drawn lazily and cached; measure with a font that has
    twenty stylistic sets.
11. **Match as a mode.** The canvas reads a derived comparison (B replaced by
    the proposal) while the model's comparison stays untouched until Apply,
    which keeps the existing guarantee. The ranking stays bound to the applied
    comparison, so the index line costs nothing while searching. The band keeps
    the `Cancel matching` identifier so the fuzzer can still tell the mode;
    window scope rules learn a mode that is not a sheet. Opening the band moves
    the canvas 76 pt: snap, do not animate, so the text does not reflow per
    frame.
12. **Language sheets.** Each category's grid is one drawn view with one
    accessibility element, not a view per character; CJK inventories run to
    thousands. Missing characters are the only per-character elements.
13. **Coverage gate.** Logic goes into models with package tests: relation text,
    the decimals a pair of numbers shows, speaker figures, per-setting and
    per-section "changed", table sorting, header column rules by width, the
    search routing rule, the united feature rows, the derived comparison. Views
    stay thin, with one condition per small subview.

Not needed by this design, so not problems: editing the sample in place (the
sheet stays), a sidebar's width budget, a joined slider, a settings band that
pushes the page (only Match does).

## Decisions

The owner approved the design on 15 November 2026. Each item carries its state:
**Decided** was ruled on by the owner; **As drawn** is part of the approved
design and was not discussed on its own; **Open** awaits a ruling.

1. Decided. **Light only, chrome included.** The HIG neither endorses nor
   forbids it. The window is the page; shared ink must be black on white.
2. As drawn. **Guides are neutral with letters**, not red and blue as in today's
   app. Red and blue then mean the two inks and, with decision 15, the letters
   that name the two fonts; never a line.
3. Decided. **A missing glyph still draws the other font's ink**, in its colour,
   in the overlay. Today's app draws nothing there and says "Character
   unavailable".
4. As drawn. **Match is a mode, not a sheet**, and loses the two "Hamburg"
   previews to the live canvas. Browsing stays possible while it is open.
5. Decided. **Languages sorted by speakers** by default. Today's list is
   alphabetical.
6. As drawn. **No Undo button in the toolbar.** The Edit menu remains.
7. As drawn. **No facts in the header.** Units/em and x-height are in the Glyph
   table (units and em) and the inspector's facts (em) only; the header says
   what the fonts are called and how they are set. The alternative, two more
   columns at full width, duplicated ten values and filled the white between the
   header's two halves.
8. As drawn. **Typography matched across fonts.** If uniting AAT and OpenType
   features proves unreliable, the fallback is the same table with a row per
   feature per font.
9. As drawn. **The inspector sits under the toolbar** so the toolbar never
   moves. If the system insists on a full-height pane on macOS 26, the view
   switch shifts when it opens.
10. As drawn. **⌥⌘1 and ⌥⌘2 change meaning** to "Font A" and "Font B"; ⌃⌘I shows
    the inspector.
11. As drawn. **The sample is edited in a sheet**, as today. Editing in the
    column was weighed and left out for its risk (input methods, undo,
    mirroring).
12. As drawn. **Wording.** "Not installed" replaces "Font unavailable" in the
    header; "Use Checked as Specimen" replaces "Use as specimen"; "B is not
    installed. Choose an installed font to compare." is new, for the index line;
    the picker gains the column head "Distance". "Minimum speakers", "Character
    unavailable", "No shared characters to compare." and the Match texts are the
    app's.
13. Decided. **One bar per index cell**, the score ranked by. With Shape and
    Spacing both on the app ranks by the sum of two percentile ranks, and the
    bar is that sum; the two parts are in the help tag.
14. Decided. **Decimals of typed values.** Size, explicit leading, tracking and
    axis values show as many decimals as the more precise of A and B needs, the
    same on both, so the default header stays `22 pt` and `0 em`. The accepted
    cost: committing `21.46` in B rewrites A's `22` as `22.00`, though A's value
    has not changed, and an explicit leading beside an automatic one reads
    `28.000 pt`. Measured and computed values always show three decimals and
    font units none (see Numbers). The alternative, fixed decimals for typed
    values too, was turned down because the default header would read `22.00 pt`
    and `0.000 em`.
15. Decided. **The letters A and B carry the colour throughout; the key squares
    are gone.** Every letter that labels a font is bold in that font's colour,
    in the header, the canvas, the inspector and the Languages page, and the key
    is three coloured words. The owner chose this over keeping the colour to the
    header: every label is keyed where it stands, at the cost of red and blue
    letters on pages where no ink is being compared. As drawn with it: A's
    letter stays red when B is None or not installed, although nothing red is
    then drawn; with Differentiate Without Color the key regains two small
    hatched squares, because a word cannot show a hatch; and Swap stands at x
    34, centred over the letters.
16. Decided. **Speakers under one million are shown in whole thousands**
    (`250k`), and under a thousand as the count. The filter's own value keeps
    its decimal (`8.3M`): it is the threshold the app documents, not a row of
    the list.
17. Decided. **Accessibility identifiers may change.** Recorded fuzz traces
    replay the names they saw, so renaming a control breaks them. The owner
    ruled that a complete rebuild is worth losing the traces recorded before it.
    The rebuild gives controls the identifiers the design needs, regenerates the
    fuzz corpus, and keeps the fuzzer paragraph of `AGENTS.md` naming the
    controls in use.
18. Decided. **The Languages list** shows speakers in whole millions and no
    language code, and the detail's facts line omits the language's own name
    when it repeats the title.

## Notes on the mockups

Real, from the font files, the app's data or today's screenshots:

- Units per em, x-heights, automatic leadings, and the metrics of U+0040 and
  U+0198.
- The first fifteen characters of the Shape + Frequency ranking, in today's
  order.
- Language names, codes, speaker counts and the 108-language count; the coverage
  marks, computed from the two fonts' character maps and checked against the ten
  rows visible in today's screenshot; the English inventory and its counts.
- That Helvetica Neue has no glyph for U+0198 and Arial has one (asserted when
  the pages build).
- Feature names and tags in the inspector; every quoted string of the app.

Computed here, so approximate: ranks 16 to 22 of the Shape + Frequency line and
the whole Shape + Spacing line in `glyph.html` (the app's formulas with FreeType
in place of Core Text), whose bars are the sums of percentile ranks and so are
all long among the first 22 of 99; the automatic leadings at 21.5 and 21.46 pt.
The overlays in the index cells are the browser's drawing of the real outlines;
only their order is approximate.

`glyph.html` is drawn with Shape and Spacing on and Frequency off, so that
U+0040 is first in the line and the selection mark shows; `text.html` and the
others show the default, Shape and Frequency.

Invented: the bar lengths of the Shape + Frequency line (the computed scores
laid along the app's order); similarity distances and "Compared 40 of 240"; the
settings in `detail.html`; the Match proposal, distances and evaluation count;
`Univers-Roman` as the font that is not installed; the focus ring in
`missing.html`, drawn neutral where the system's would take the accent colour.

The toolbar is drawn as plain capsules; real glass is the system's. Text columns
are clipped to whole lines; in the app they scroll.

No drawn state has a pair of typed values with different numbers of whole
digits, so the right-alignment of a header pair is specified above and not
shown.

### Regenerating

In `mockups/`, `uv run --no-project --with fonttools python3 build.py` writes
the pages as HTML beside the script (git ignores them) and `check.py` verifies
them statically. The renders are those pages in headless Chromium with a 1440 x
900 viewport at a device scale factor of 2. The pages draw Helvetica Neue and
Arial from the system, so they build and render on macOS only. `data.py`
rewrites `data.json` from the two font files and the language data in
`Sources/TypefaceCore`; it also needs Pillow.

The design was chosen from four candidates drawn from scratch and judged by eye;
"Two Lines" in this document is the candidate the final design is built on. The
candidates are not kept.
