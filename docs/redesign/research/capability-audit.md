# Capability audit: four Typeface/Off redesigns

Written during the design round, about four candidate designs (three-column,
one-sheet, triptych and Two Lines). The final design in `../spec.md` is built on
Two Lines; the candidates' specs and renders are not kept.

Sources: README "Use" section (lines 83-172), `WorkbenchCommands.swift`,
`WorkbenchView.swift`, `FontInspector.swift`, `FontFamilyPicker.swift`,
`MatchSheet.swift`, `LanguageBrowserView.swift`, `GlyphComparisonView.swift`,
the four specs, and all 16 renders. Looks are not judged. "Weakened" means
harder, slower, hidden or less certain to reach; the spec's own argument is
given with my view.

## 1. Capability inventory (today's app)

Fonts

1. Family picker per side: popover, search focused, up/down highlight, Return
   chooses, Escape dismisses, nothing changes until confirmed.
2. Style pop-up per side.
3. B = None (inspect one font); reselecting the family restores its previous
   settings.
4. Name / Similarity sort in B's picker; distance per row; progress; Pending and
   Unavailable rows stay selectable; caption stating the basis.
5. Swap fonts (including settings), toolbar and Option-Cmd-S; disabled without
   B.
6. Missing font: labelled "Font unavailable" (orange) with PostScript name;
   nothing drawn in fallback. Match unavailable.

Appearance 7. Link/unlink (lock per inspector); ratio and offsets preserved,
including through clamps. 8. Size (10-144), tracking, weight (read-only on a
static font), every variable axis, each with slider, field, unit. 9. Leading
1-288, Auto checkbox (computed value shown), linked-Auto rules (entering a value
sets both; reset restores Auto to both); explicit leading fixed when size
changes. 10. Reset per setting, reset per section (Reset appearance / Reset
typography), always visible, disabled when default. 11. Shared size field: set
both sizes to one value even when unlinked; "Mixed" when they differ. 12.
Typography: per-font feature lists (Common, Variants, Numbers, Automatic shaping
collapsed), checkbox or pop-up, live before/after preview, "No preview
available", OpenType tag shown, never linked. 13. Match: sheet, Optimize per
setting, Stop, Cancel, Apply (one undo, recalibrates links), 15 s / 2,048
evaluations budget, "No better value found" message, experimental-heuristic
note, unavailable unless both fonts installed.

Text view 14. Sample pull-down (built-ins + Custom), Edit text sheet
(Cancel/Apply), Shift-Cmd-E. 15. Highlights of differing characters in red/blue;
click to inspect. 16. Differences strip: ranked characters, bars (weighted over
measured), tooltip (frequency, weight), Shape / Spacing / Frequency toggles,
progress while ranking, empty state; hidden when B = None or in Languages.

Glyph view 17. Overlay red/blue/black; baseline, x-height, advance guides; Shape
aligns ink, Spacing alone aligns origins; scale and baseline fixed while
navigating. 18. Metrics (advance, LSB, RSB; units and em; x-height,
units/em). 19. Navigate: arrow keys, previous/next buttons; click a strip
item. 20. Type a grapheme in character field + Return (any Unicode
character). 21. Find Character (Cmd-F; click the name): by name, character, or
U+ code point; up/down/Return/Escape. 22. Zoom 100-800 % (wheel, pinch at
pointer, slider, +/- buttons), pan, click percentage to reset; click canvas at
100 % returns to Text. 23. Missing glyph labelled, never fallback.

Languages 24. Languages view (Cmd-3); search; logarithmic speaker filter (8.3M
default, All), Show historical, coverage filter, Clear filters,
hidden-orthography notice, empty states, count. 25. Rows with name, ISO code,
speakers, A/B coverage status. 26. Orthography selection; per-category coverage;
character sheet categories; missing characters per category (buttons that
inspect); caveat; Sources and notes. 27. Use as specimen (one Undo step).

Window and menus 28. Menus: Edit > Find; View > Text/Glyph/Languages
(Cmd-1/2/3), font A/B inspector toggles (Opt-Cmd-1/2), Shape/Spacing
(Shift-Cmd-1/2), Frequency (Shift-Cmd-F); Comparison > Match (Shift-Cmd-M), Swap
(Opt-Cmd-S), Edit Sample Text (Shift-Cmd-E). Commands disabled while sheet
open. 29. Undo/Redo: toolbar Undo button + Edit menu; browsing, view switching
and highlight toggles preserve Undo; undoing a font edit keeps the inspection in
view. 30. Multi-window, each independent, state discarded on close; window title
names the fonts. 31. Tooltips, accessibility labels (every control is a labelled
button/field).

## 2. Cross-design findings (all four)

- **Toolbar Undo button removed in all four.** Argument: Edit menu is where Mac
  users look. View: acceptable but weaker. It was the only on-screen sign that
  something is undoable after a Match Apply or Use as specimen. Redo was never
  on screen, so nothing else is lost.
- **Light only (all four).** Argument: shared ink must be black on white. View:
  sound for the canvas. The app no longer follows the system appearance;
  Increased Contrast and Dark Mode users get no option. Not a capability loss,
  but state it as a decision.
- **Zoom slider removed in all four.** Continuous zoom is left to wheel and
  pinch. Mouse-only users with no wheel have only +/- or discrete steps.
  Acceptable, but only the three-column and triptych designs keep
  click-percentage-to-reset on screen; one-sheet and Two Lines put reset in a
  pop-up and Cmd-0.
- **Match becomes a non-sheet mode in all four.** Argument: HIG says use a panel
  when people repeatedly provide input and observe results. View: an improvement
  (judging on the real specimen). Specs leave unclear: whether view switching
  stays available during Match, the "No better value found" message, the budget
  text, the "choose two installed fonts" empty state, and what happens with a
  missing font.
- **Find Character and the character field merge into one search field in all
  four.** Improvement for one place to look. Weakened: README promises "type a
  grapheme and press Return to inspect any Unicode character". Typing `a` is
  also a valid name search; the specs say Return inspects the top result
  (three-column) or give no rule. Whether a typed grapheme is inspected first,
  whether multi-code-point graphemes (e + combining acute) work, and whether
  characters not in the ranking are reachable is unspecified in all four.
- **The search field is reused for Languages** (three-column, triptych, Two
  Lines, one-sheet). Cmd-F in Languages view is unspecified in all four; today
  Cmd-F is a character search.
- **Missing-font and error styling lose the orange warning** in three-column,
  one-sheet and triptych (secondary ink "Not installed"). A missing font is easy
  to overlook in a design where the name still sets in the system font. Two
  Lines uses ink plus a warning symbol, which is better.
- **Previous/next character buttons removed** in three-column, one-sheet, Two
  Lines (menu commands and arrow keys remain). Triptych keeps chevrons.
- **Differences strip no longer shows a button-per-tile with border**; all keep
  click, bars, tooltip, three toggles.
- Not addressed by any spec: shortcuts for Reset, behaviour of linked Auto
  leading with only one side Auto (except where noted), range limits (10-144
  size, 1-288 leading) shown to the user, per-axis ranges when axes differ
  between fonts, what Swap does when B = None, empty ranking state ("No shared
  characters to compare") and "No languages match these filters".

## 3. Per design

### three-column (sidebar of ranked characters, paper, one inspector)

Lost / weakened / slower

- **Shared size field and Mixed removed.** Argument: linked Size row drives
  both; masthead shows each size; "Comparison > Make Sizes Equal". View:
  weakened. Linked editing keeps the ratio, so setting both to exactly 18 pt
  when the ratio is not 1 needs the menu command, and that command appears only
  in the removal table, not in the menus paragraph. README promise "press Return
  to set both sides" is gone. Also `Mixed` has no on-screen replacement beyond
  comparing two numbers.
- **Differences controls and the ranked list live in the sidebar.** The sidebar
  auto-closes below 916 pt wide; Shape/Spacing/Frequency checkboxes and the list
  disappear with it. Shortcuts remain, but reaching ranked characters then needs
  Cmd-F. Slower at narrow widths only.
- **Settings stay reachable but the inspector closes under 1248 pt** (auto). At
  1200 pt the first thing the user loses is size/leading/tracking. It reopens
  from the toolbar.
- **Match… unreachable?** It is in the toolbar; fine. But in Match mode the
  inspector's "before -> after" replaces B's controls, and other edits are
  disabled: same as today.
- **Inspector shortcuts changed** (Opt-Cmd-1/2 to Ctrl-Cmd-S / Ctrl-Cmd-I):
  muscle memory loss, trivial.
- **Missing glyph in the ranked list** is covered ("No glyph in Arial", empty
  advance box). Missing font covered in masthead, paper, inspector. Orange
  warning lost.
- **Language list loses the one-line speaker filter header**: the speaker filter
  is still in the sidebar (render confirms field, slider, Coverage, Show
  historical, Clear filters). No loss.
- **Edit sample text** is still a sheet. Same as today.
- **Reset**: icon appears only when value differs; section "Reset" only when
  changed. Argument: nothing at rest. View: improvement for scanning; one cost
  is that "reset leading to Auto" is not discoverable when leading is already
  automatic (fine, nothing to reset).

Improved

- One inspector, A and B on one row per setting; features matched by feature id
  so a missing feature is a dash (render confirms).
- Ranked list shows name and code point (today's tiles show glyph and bars
  only), 17 rows visible vs 15 tiles.
- Language list: two marks under A and B heads; ISO code and speakers kept;
  orthography tape and checkboxes combine five paragraphs into five rows;
  missing characters are clickable buttons that inspect.
- Hero overlay larger, with metrics as one tape.
- Always-visible settings (inspector open by default): fastest design for
  tracking/axes/Auto.
- Weighted bar plus Spacing bar (two bars) matches the Shape/Spacing toggles.

Unclear in spec

- Where the hidden-orthography notice goes (listed only as "hidden-match
  notice").
- Whether Cmd-F in Languages searches characters or languages.
- Which axes appear when A and B have different axes.
- Undo of Make Sizes Equal; Make Sizes Equal not in the menu list.
- Language-sheet default checked categories: render shows Base only checked.
- Light-only means sidebar vibrancy is replaced by an opaque ground on macOS 15;
  "unverified" per the spec.
- Render notes: nothing broken. The key letters A/B are the only colour in the
  masthead; the guides are coloured red/blue in the hero (open decision 1).

### one-sheet (bands, no panels, folded settings)

Lost / weakened / slower

- **All settings except size and leading sit in a closed fold.** Tracking,
  weight/axes sliders, Auto leading, link toggle, typography features, reset:
  one extra click, then the fold scrolls inside half the content height. The
  masthead states non-default settings ("Tracking 0.01 em"), which helps, but
  sliders and the link toggle are hidden. Slower to reach; argued as "adjusted
  occasionally". View: reasonable for appearance, a real cost for the tool's
  core purpose (tune B until it matches A) because the preview shrinks while the
  fold is open.
- **Differences strip shows ten characters** (render shows nine at 1440) vs 15
  today, no names or code points. The ranking is the app's central result; this
  is the weakest ranked-list design. Scrolls horizontally.
- **Shared size / Mixed merged into masthead sizes.** Linked editing sets the
  other by ratio; Option-Return sets both to the typed value. View: weakened and
  hidden. The key gesture is undocumented on screen.
- **OpenType tags moved to tooltips/VoiceOver hint.** Weakened for type
  designers, who read tags (kern, liga).
- **Typography rows not matched by feature.** Spec: "A's features in A's column,
  B's in B's". Render shows two independent lists, so which font lacks a feature
  is not visible, unlike three-column and Two Lines.
- **Language list loses ISO code and speaker count per row** (render: names and
  squares only). The speakers filter is a one-line statement that opens a
  popover; filter is slower to adjust (two steps). Squares, not dots; no key
  explaining filled vs hollow in the render.
- **Edit text in place** (caret in column A, B mirrors; Escape or Cmd-Return
  ends). No Cancel; Escape ends. Today's sheet had Cancel/Apply. Weakened; see
  unclear.
- **Metrics move under each font's own glyph** (two tables) rather than side by
  side: comparing advance values means looking across 700 pt.
- Zoom moves to a pop-up (100/200/400/800); coarse and no live percentage
  click-reset.
- Reset: per row only when changed; section/all resets in context menu and
  Comparison menu only. Less discoverable than today's section Reset button.
- Missing font: row in fold for a missing font unspecified.

Improved

- Settings summary in the masthead ("22/26.616 pt", departures) makes the
  specimen self-describing; size and leading editable in place.
- Single link toggle plus "Link Appearance" menu command; Reset All command.
- Inspector shortcuts keep Opt-Cmd-1/2 and now focus A's or B's first control:
  improved keyboard access.
- Find field in toolbar, with unavailable-in-font rows labelled.
- Language sheet shows every category in both fonts; missing characters in place
  plus clickable.
- Cmd-0, Cmd-+/-, View > Previous/Next Character are real menu commands.

Unclear in spec

- How a user returns to the list of language orthographies (render shows a
  tab-like "Latin (Latn)").
- Whether the hidden-orthographies notice survives.
- Behaviour of Auto in linked mode when one side is Auto.
- Edit-in-place with missing glyphs, bidi or IME, and whether Escape discards or
  keeps.
- Whether Match is blocked while the fold is closed.
- Under 1200 pt the margin controls fold into caption rows; the Differences band
  at 880 wide is ten characters at a tenth of the width.
- Render notes: detail render's popover points at the style area; the picker
  anchors per spec to the family name. In the detail render the link toggle and
  B's sliders are hidden under the popover.

### triptych (A | centre | B)

Lost / weakened / slower

- **Register hidden by default** and nothing in the masthead says whether
  appearance is unlinked, tracked or leaded explicitly (masthead shows facts
  only: units/em, x-height, and size only when sizes differ). A changed state is
  invisible until the register is open. View: weakened versus both always-open
  inspectors and versus one-sheet's departures line.
- **Typography lists per font are in outer zones**, not matched row to row
  (render: A and B lists differ in order and content). Comparing which font has
  which feature requires reading two lists. Both lists scroll inside a register
  that is up to 40 % of the window.
- **Missing glyph is covered only for the languages sheet** (dotted empty
  cells). The overlay, the ranking miniatures, text and the metrics are
  unspecified for a glyph that one font lacks.
- **Missing font**: masthead and column covered; register behaviour unspecified.
- **Appearance axes: "one row per shared axis".** Axes that only one font has
  are not mentioned. Possible loss.
- **Edit in place**: Done/Escape ends it (no Cancel). Same issue as one-sheet.
- **Ranking list in Text has no names or code points** (render: glyph and bar
  only). 19 rows visible (improved count) but names are hover-only.
- **Language list needs a Filter popover** for speaker filter, coverage and
  historical: slower than always-visible. The header shows the active filter.
  Language sources and notes move into an info popover (one more click).
- **Languages sheet default checks four of five categories** in the render
  (Currency off), unlike today's default; confirm against the app.
- **Cmd-F and the search field** double as Languages search (prompt changes).
  Same ambiguity as above.
- **Swap** moves to the toolbar (icon-only) with Opt-Cmd-S: fine.
- Zoom scope with three equal columns (does zoom apply to the solos or only the
  overlay?) unspecified.

Improved

- Keeps shared size with Mixed (the only design that does), placed on the axis.
- Link relation written out per row (B = 0.977 x A, B = A + 0.004 em): the
  preserved ratio becomes visible. Clamped fields shown in secondary ink. Best
  treatment of the linked-appearance rule.
- Edit text in place (one Undo group); register keyboard focus via Opt-Cmd-1/2
  is kept.
- Metrics placed at the guides they measure; ranked grid of 30 in Glyph,
  arrow-key stepping.
- Previous/next chevrons kept at the name.
- Language rows show speakers and coverage dots with a Complete/Incomplete key;
  missing characters in place in a fixed grid so position is comparable.
- Match inside the register with B's column drawing the proposal; Apply enabled
  only on a verified improvement.

Unclear in spec

- Auto leading per side in the tape when one side is Auto and linked.
- Whether the tape row labels "B = A + 40" extend to every axis in the render
  (render shows only size/tracking).
- What happens to the register's Typography zones when only one font is
  installed or B = None.
- The Differences heading baseline alignment depends on the two first baselines
  matching; effect when sizes differ much.
- Render notes: B's masthead line is cut off by the picker in detail.png only
  because the picker overlays it; nothing else broken. The Glyph tags are
  reversed "B A ... A B" at the overlay edges, correct but order-confusing.

### free ("Two Lines": A row over B row)

Lost / weakened / slower

- **Auto leading is an empty field with a placeholder.** Argument: one control
  instead of two. View: weakened. To keep Auto off at the current computed value
  one must type the same number; fail-fast on invalid input and the 1-288 range
  have no visible hint; clearing the field is the only route back to Auto.
  Per-side Auto in the inspector (a single Auto checkbox on the label line)
  while unlinked is not specified.
- **Specification rows only hold fields, not sliders.** Slider ranges and clamps
  are visible only in the inspector. Axes are columns: fonts with many or
  different axes overflow (below 1000 pt they leave the rows entirely).
- **Below 1000 pt, leading, tracking and axes leave the specification** and live
  in the inspector only. Match "Optimize" buttons sit under B's columns; where
  those columns have left, reaching them is unspecified.
- **Features: one row per feature, previews only for the selected row.** Argued
  as one third of the height. Weakened: the all-previews-visible scan is gone
  (today's feature previews are the main aid for choosing a feature).
- **Typography summary** is a one-line button ("Monospaced Numbers,
  Discretionary ligatures"); the inspector is closed by default, so every
  feature change is two steps.
- **Sample edit stays a sheet**; fine.
- **Index line shows ~20 characters, no names**, scrolls horizontally; click or
  arrow keys step. Under 900 pt the three toggles collapse into a pull-down
  (slower).
- **Language list: no orthography per-row control and no hidden-orthography
  notice specified.**
- **Reset**: section reset only in menu (Reset Appearance / Reset Typography);
  inspector shows a per-label reset. Less discoverable.
- **Set both sizes**: two fields plus "Equalize Sizes" menu command (not shown
  on screen). Same weakening as three-column.
- Mixed removed; two fields always visible so nothing is hidden.

Improved

- The comparison gets the whole window (58 % more area claimed); size, weight,
  leading, tracking, link and Match are always visible and editable in place:
  fastest design for the common task of tweaking B.
- Languages: always-visible filter line with a slider with tick labels, a
  sortable table (speakers, A, B), coverage in one table with a Missing column
  of buttons.
- Menu commands: Choose Font A/B, Link Appearance, Equalize Sizes, Reset
  commands, Zoom In/Out/Actual Size, Previous/Next Character, Show Inspector:
  the best keyboard and menu coverage of the four.
- Features matched by tag with a column per font; dash if absent.
- Missing-glyph state in the figure's place and a dash in the table; errors in
  ink with a warning symbol.
- Accessibility section; ink vs secondary-ink convention (editable vs computed).
- Match bar: Optimize under each B column and an "Optimize Feature" pull-down,
  status, heuristic note, Cancel/Apply.

Unclear in spec

- Match when the inspector is open or the width is under 1000 pt (see above).
- Link toggle semantics for Auto leading (single toggle) and what the single
  Auto checkbox does when unlinked.
- Whether "Weight" stays editable for variable fonts without a wght axis.
- Interplay of Linked and the typed Size fields (ratio).
- Render notes: nothing broken; the font-name rows set in each font, with a
  fallback to the system font if the font cannot draw its own name. Detail
  render shows the inspector open with Typography column removed from the rows,
  as specified.

## 4. Ranking by capability preservation (my view, not looks)

1. Two Lines: loses the fewest daily capabilities; weakened on
   Auto-by-empty-field, per-row previews, and narrow-width settings.
2. three-column: loses the shared-size gesture (menu only), nothing else of
   substance; everything stays visible by default.
3. triptych: strongest treatment of linking and the shared size, but settings
   are hidden by default, typography lists unmatched, and missing-glyph states
   are incomplete.
4. one-sheet: most hidden (fold), ten-character ranking, no speaker/ISO in
   language rows, tags to tooltips.
