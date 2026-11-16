# Buildability of the four fresh designs (SwiftUI/AppKit, macOS 15+, tested on 15, 26, 27)

Written during the design round, about four candidate designs (three-column,
one-sheet, triptych and Two Lines). The final design in `../spec.md` is built on
Two Lines; the candidates' specs and renders are not kept.

Scope: how each structural idea would be built, what the system gives, what is
custom, what is unknown without a prototype. Rewrite cost is not counted against
any idea. I looked at all 16 renders and read the four specs, `platform-api.md`,
`hig.md`, and the app sources named in the brief.

Evidence conventions. "Verified" means read through `cupertino` (URIs given);
items from `platform-api.md` were verified by that report and I re-checked the
ones marked "(re-checked)". "Unverified" means from memory. "Code" means I read
it in `Sources/TypefaceOff/`.

Sizes: S = days, M = 1-2 weeks, L = several weeks, XL = a quarter-sized rewrite
with its own stabilization.

## 0. What the app is today, because it sets the cost of every idea

- `TypefaceOffApp.swift`: one `WindowGroup`, `.preferredColorScheme(.dark)`,
  `minWidth: 1080`. `WorkbenchView` is a hand-built `HStack`: `InspectorPanel`
  (A) | main column | `InspectorPanel` (B). No `NavigationSplitView`, no
  `.inspector`, no `.searchable`.
- The paper is already a locally forced light surface (`.background(.white)` +
  `.environment(\.colorScheme, .light)` on specimen, glyph view, popovers,
  sheets). So "light paper" is not new; "light window and light toolbar" is.
- `InspectorPanel` keeps the inspector alive at width 0 with
  `.clipped().disabled().allowsHitTesting(false).accessibilityHidden(true)`,
  with the comment "Retain disclosure and scroll state while the inspector is
  collapsed". The author needed that. Anything that replaces it with a system
  pane has to answer the same question (see idea 2).
- Specimen text is an `NSTextView` (`SpecimenNSTextView`, TextKit 1
  `NSLayoutManager`) in an `NSScrollView`. Glyph view is an `NSScrollView` with
  `allowsMagnification`, 1x-8x, custom wheel/pinch/smart-magnify
  (`GlyphScrollView`). The differences strip is already a
  `ScrollView(.horizontal)` + `LazyHStack` of buttons
  (`WorkbenchView.differences`). The font picker, character search and Match are
  already popovers/sheets with the Name/Similarity switch, search field
  (`PickerSearchField`, an `NSSearchField` wrapper), progress,
  "Pending/Unavailable" rows. Metrics, link math (`comparison.link?.sizeRatio`,
  `calibrate()`), ranking, fit (`FontFitModel`) are models, not views.
- Consequence: all four designs are mostly a re-layout and re-skin of existing
  engines. The new engineering is in a handful of places (idea 6 window-wide
  baseline, idea 7 union typography table, idea 9 live Match, idea 10 in-place
  editing, idea 1 neutral selection/focus) plus the test and fuzzer contract
  (idea 14).

## 1. One paper ground under a system toolbar, light only, neutral tint, focus rings, selection

How to build.

- Window: `WorkbenchWindow` flips `.preferredColorScheme(.dark)` to `.light`.
  Documented: `apple-docs://swiftui/view/preferredcolorscheme(_:)` (macOS 11,
  "nearest enclosing presentation... window"). Menus, the menu bar and the
  Window/Dock chrome are not part of that presentation; add
  `NSApp.appearance = NSAppearance(named: .aqua)` in `TypefaceOffAppDelegate`
  (property documented: `NSApplication.appearance`, article
  `apple-docs://appkit/choosing-a-specific-appearance-for-your-macos-app`).
  Whether `preferredColorScheme(.light)` alone also lights context menus and the
  font picker popover: unverified; the popovers already force `.light`
  themselves.
- Ground: `.containerBackground(paper, for: .window)` (macOS 15.0+,
  `ContainerBackgroundPlacement.window`,
  `apple-docs://swiftui/containerbackgroundplacement`) so paper runs behind the
  toolbar; set `toolbarBackgroundVisibility(.hidden, for: .windowToolbar)`
  (macOS 15.0+) to stop the pre-26 toolbar painting its own material. Remove the
  manual `.background(WorkbenchStyle.panel)`. Delete the dark `WorkbenchStyle`
  colors; keep `red`/`blue`.
- Content under the toolbar: scroll views (the specimen `NSScrollView`, glyph
  scroll view) automatically scroll under the toolbar on 26 with the system
  scroll edge effect; tune with `scrollEdgeEffectStyle(.soft|.hard, for: .top)`
  (macOS 26 only, `apple-docs://swiftui/scrolledgeeffectstyle`). Do not add
  `#available(macOS 26)` code to gated files (see idea 14); take the automatic
  behavior.
- Neutral tint. `.tint(...)` is documented as "always respected"
  (`apple-docs://swiftui/view/tint(_:)`) and colors SwiftUI checkboxes, sliders
  and buttons. It does not reach: the focus ring (system
  `keyboardFocusIndicatorColor`, derived from the user's accent), `List`/`Table`
  row selection (system `selectedContentBackgroundColor`), or `NSTextView`
  selection by default. Names verified in
  `apple-docs://appkit/ui-element-colors`. Fix per surface: `NSTextView`
  selection and caret (`selectedTextAttributes` is from memory, unverified;
  `insertionPointColor` verified
  `apple-docs://appkit/nstextview/insertionpointcolor`); `List`/`Table`
  selection needs a custom row background or an AppKit row view (see idea 12);
  focus rings can be hidden with `focusEffectDisabled(_:)` (macOS 14.0+,
  verified) only if every control draws its own visible focus state, otherwise
  keyboard users lose focus (HIG: keyboard-only use). The accent color in the
  asset catalog is honored only when the user's accent setting is Multicolor
  (`apple-docs://swiftui/color/accentcolor`, HIG color), so a user whose accent
  is red or blue will see red or blue selection and focus in chrome. Red/blue in
  the specimen are unaffected (drawn by the app).
- Light-only is permitted but not endorsed: HIG dark-mode names only dark-only
  for immersive media (hig.md section 2). Treat as an owner decision already
  made.

macOS 15 vs 26/27.

- 15: toolbar is a titlebar material; with
  `toolbarBackgroundVisibility(.hidden)` paper shows through. Sidebar (if used)
  is full-height vibrancy, not paper (see idea 2). Controls are classic Aqua;
  the segmented switch has a pale bezel.
- 26: toolbar items become glass capsules (what the renders show); standard
  controls get new shapes; sidebar and inspector float as glass over the detail.
  Glass over pure white is nearly invisible; that matches the renders, but it is
  an untested look.
- 27: the beta notes in the index
  (`apple-docs://macos-release-notes/macos-27-release-notes`) say nothing that
  changes this idea.

Size: M. Risk: the neutral tint is only partial; focus ring and accent-colored
selection are the leaks, and Increase Contrast / Reduce Transparency change how
paper meets glass. Evidence: code (`WorkbenchWindow`, `.background(.white)`
pattern); `platform-api.md` sections 3 and 6; hig.md section 2. Unknown without
a prototype: how a flat paper window looks under the 26 glass toolbar and 15
titlebar with the hidden-background modifier.

## 2. NavigationSplitView sidebar + trailing `.inspector` versus no panels

Used by: three-column (sidebar + inspector), free (inspector only, closed by
default). Triptych and one-sheet use no system panes.

How to build (three-column).

- Replace the root `HStack` with
  `NavigationSplitView { sidebar } detail: { paper }` plus
  `.inspector(isPresented:) { settings }`. `NavigationSplitView` macOS 13
  (`apple-docs://swiftui/navigationsplitview`); `.inspector` macOS 14
  (`apple-docs://swiftui/view/inspector(ispresented:content:)`); widths via
  `navigationSplitViewColumnWidth(min:ideal:max:)` and
  `inspectorColumnWidth(min:ideal:max:)` (both documented).
- Sidebar content: `List(selection:)` with `.listStyle(.sidebar)` (macOS 10.15,
  `apple-docs://swiftui/liststyle/sidebar`). It switches on mode: differences
  list in Text/Glyph, language list in Languages.
- Toggles: the sidebar toggle is automatic
  (`ToolbarDefaultItemKind.sidebarToggle`). There is no automatic inspector
  toggle; add a toolbar `Button` bound to the `isPresented` flag (the Landmarks
  sample does this), and add `InspectorCommands` (macOS 14, Control-Command-I)
  to `WorkbenchCommands` for the menu bar (HIG: every toolbar item as a
  command).
- Free (inspector only): same `.inspector` on a plain detail view; closed by
  default; nothing else needed.

What the system gives: sidebar/inspector collapse and resize, window-restoration
of the presented flag ("Trailing column inspectors have their presentation state
restored by the framework"), 26 glass floating panes, the sidebar toggle,
View-menu items with `SidebarCommands`, thin dividers.

What must be custom: the inspector toggle button; any view state that must
survive hiding. The docs are silent on whether hidden inspector content keeps
`@State` (re-checked in `platform-api.md`; the Landmarks sample uses an external
`@Observable`). Assume it does not, and move `collapsedGroups`, scroll position,
and expanded sections into `WorkbenchModel` or `@SceneStorage`. That is a small
change; `InspectorPanel`'s 0-width trick is the fallback if the assumption is
wrong.

Space budget, a real finding. Three-column at the current minimum window width
1080 leaves 1080 - 260 (sidebar) - 332 (inspector) = 488 pt for the detail, but
the Text view needs two columns of about 360 plus the gutter (the mock uses 768
content width). Either raise `minWidth` to about 1360 (the app today is usable
at 1080 because only 2x246 of panes show), or let the panes auto-collapse via
`columnVisibility`, or let the inspector overlay. HIG: "Consider automatically
hiding and revealing a sidebar when its container window resizes" (hig.md).
Decide before building; it changes the whole layout contract.

macOS 15 vs 26/27.

- 15: the sidebar is a full-height vibrancy material tinted by the desktop
  (graphite accent adds wallpaper tint: HIG dark-mode, `platform-api.md`). It
  will not be paper-white. That breaks the "one sheet" idea of idea 1 on 15
  unless the sidebar is custom-built. Mocks show the 26 look (rounded floating
  glass sidebar).
- 26: sidebar and inspector float; the detail view extends beneath them and is
  inset by the sidebar's width in its safe area
  (`apple-docs://macos-release-notes/macos-26-release-notes`).
  `backgroundExtensionEffect()` (26) is for images; on flat white it should be
  invisible (unverified).
- 27 beta: item 176879915 "For some apps, the show/hide sidebar toolbar buttons
  are missing" (release notes). Provide the View-menu command and keyboard
  shortcut as a fallback.
- `.inspector` leading edge: not available (docs mention trailing only). Nothing
  in the four designs needs leading.

No panels (triptych, one-sheet): a `VStack` of bands under the system toolbar.
Size S, and it has no state-retention or width problems, but it also gives up
system sidebar/inspector commands and fluid column resizing; every region is
then hand-managed.

Size: three-column shell M (S for free). Risk: pane widths vs minimum window;
the 15 sidebar material; inspector state loss. Evidence: `platform-api.md`
section 1; code `InspectorPanel.swift`, `WorkbenchWindow.frame(minWidth: 1080)`.

## 3. Typeset masthead: font names as pickers, popover with search and Name/Similarity

Used by: all four (three-column, triptych, one-sheet masthead; free as a
two-line specification).

How to build.

- A `Button` with `.buttonStyle(.plain)` whose label is `Text(family)` set in
  the font itself plus a chevron, with `.popover(isPresented:)` presenting the
  existing `FontFamilyPicker` unchanged. The picker already has
  `PickerSearchField`, the Name/Similarity segmented control, "Similarity to X",
  progress, `Pending`/`Unavailable` rows that stay selectable, key handling
  (up/down/return/escape). That is most of the work, done.
- Rendering the name in its own face: build a `Font` from the Core Text font
  used for the specimen (`Font(CTFont)`; availability from memory, unverified)
  or `Font.custom(postScriptName, size:)`. `Font.custom` silently falls back
  when the face is missing, which the app forbids; so branch on
  `FontRenderer.isAvailable(config)` and show the system font in secondary ink
  with "Not installed" (what the triptych spec says). This is the one subtle
  point; the plain-Text approach would draw a substitute.
- Style pop-up: `Picker(...).pickerStyle(.menu)` with
  `.menuStyle(.borderlessButton)` (macOS 11,
  `apple-docs://swiftui/menustyle/borderlessbutton`, re-checked) and
  `menuIndicator` to taste. Existing `Font A style` identifier stays.
- Popover anchor and arrow: on macOS `popover` respects `arrowEdge`; omit it to
  let the system choose (`platform-api.md`). Outside-click dismissal is
  undocumented for SwiftUI `popover`; it works today.
- Size caption "22/26.616 pt" with an editable number: see idea 11.

macOS 15 vs 26/27: none functional. Popover material is glass on 26, light
because the picker already pins `.light`. Size: S for the picker reuse, M for
the masthead layout of the three variants (symmetrical A/B mirrored blocks,
flush-right B name; free's two-row grid). Risk: low; the one trap is the silent
substitute. Missing hit-target size: masthead names are 26-32 pt tall, fine; HIG
minimum control size is 20x20 (verified in hig.md). Evidence: code
`FontFamilyPicker.swift`, `FontInspector.swift` (family button and popover),
`PickerSearchField.swift`; popover HIG "one popover at a time".

## 4. Toolbar: centred segmented switch, a search field for Find Character and languages, a sample pull-down

Used by: all four, with different groupings (three-column: sample leading,
switch centre, Match trailing; triptych: switch centre, Swap/Settings/Search
trailing; one-sheet: switch centre, Match/Settings/Find trailing; free: sample
leading, switch centre, Search + inspector trailing).

How to build.

- `.toolbar { ToolbarItem(placement: .principal) { Picker("Comparison mode", ...).pickerStyle(.segmented) } ... }`.
  Apple's sample uses exactly this pattern
  (`swiftui-building-a-great-mac-app-with-swiftui`, `GardenDetail.swift`, per
  `platform-api.md`); HIG calls it allowed but second to a tab view in the main
  area (hig.md). Keep the accessibility label "Comparison mode" the fuzzer
  already knows (code).
- On the 27 beta there is a new `.tabs` picker style whose VoiceOver role is
  "tabs" (`apple-docs://swiftui/tabspickerstyle`, no availability line in the
  index; beta notes). Not usable with a deployment target of 15 without a gated
  branch; do not adopt (see idea 14 on `#available` and coverage).
- Sample pull-down: `Menu` or `Picker` with `.menuStyle(.borderlessButton)` in
  `.navigation`/`.automatic`, with the `Edit Text…` item inside.
- One search field for two jobs: `.searchable(text:placement:prompt:)` (macOS
  12, re-checked `apple-docs://swiftui/view/searchable(text:placement:prompt:)`)
  applied above the content, with the bound text and the prompt switching by
  mode ("Find Character" in Text/Glyph, "Search Languages" in Languages).
  `searchFocused(_:)` is macOS 15 (verified
  `apple-docs://swiftui/view/searchfocused(_:)`), so Command-F focus is free at
  deployment 15. Languages: the text drives `browser.filter.query` directly (it
  is a filter). Find Character is the hard half: today it is a popover with a
  results list (glyph, name in both fonts, "not in font" states) anchored in the
  glyph view. A toolbar search field has no popover anchor. Options:
  `searchSuggestions` (macOS 13) shows a suggestions list, but whether it can
  hold rich rows is unverified; or present the results in the canvas/sidebar
  region (e.g. replace the differences list with results while the query is
  non-empty) with Return confirming; or an `NSSearchToolbarItem` bridge (macOS
  11, `apple-docs://appkit/nssearchtoolbaritem`; "may collapse the search item
  into a button when the toolbar is low on space"), which is a custom toolbar
  and loses SwiftUI `.toolbar`.
- Grouping: HIG says at most three groups and no manual overflow (hig.md). Four
  of the designs' toolbars have four items (sample, switch, actions, search).
  `ToolbarSpacer(.fixed)` (macOS 26 only) splits glass groups; on 15 use
  `ToolbarItemGroup` and accept system spacing. Text-labelled "Match…" next to
  icon buttons needs a separator or it reads as one control (HIG toolbars).
- Title: remove it (`toolbar(removing: .title)`, macOS 14, verified) and set
  `navigationTitle("Helvetica Neue / Arial")` for the Window menu, as
  three-column says. HIG says leave the title empty if redundant.

macOS 15 vs 26/27.

- 15: segmented switch is a pale bezel, `.principal` centering is "the center of
  the toolbar" per docs; in practice centered in the space left between other
  items (from memory, unverified), so the render's exact centring on the window
  is not guaranteed when side items have unequal widths (e.g. three-column's
  sample pull-down on the left vs Match on the right).
- 26: items become glass capsules; the search field may collapse to a button at
  narrow widths (NSSearchToolbarItem doc). `DefaultToolbarItem(kind: .search)`
  (26) positions the system search item.
- 27: `.tabs` style; sidebar-toggle bug noted above.

Size: M. Risk: the shared search field's result presentation; four-group
crowding at 1080 wide on 15; principal centring. Evidence: `platform-api.md`
section 2; HIG segmented controls; code `WorkbenchView.controls` (picker label),
`CharacterSearchPicker.swift`, `LanguageBrowserView.filters`. Needs a prototype:
Find Character UX in a toolbar field.

## 5. The differences navigator (sidebar list, horizontal line of type, centre column), with arrow-key navigation

Common: the ranking is `Differences.ranked(...)` (a model, covered); every
variant is a view over the same array. Selecting changes
`comparison.selectedGlyph` and mode (`selectGlyph`), and ← → step the same array
(`navigate`, `comparison.neighbour(in:direction:)`).

(a) Sidebar `List` (three-column).

- `List(ranked, selection:)` in `.sidebar` style; row = mini overlay + name +
  code point + bar. Lazy (NSTableView-backed on macOS), so hundreds of rows are
  fine; the list is about 15 rows visible vs the current strip. Mini overlays
  reuse `GlyphDifferencePreview`; cache them as images keyed by glyph and font
  config, since drawing two Core Text glyphs per row on scroll is wasteful
  (unverified perf, but small).
- Arrow keys: a focused `List` moves selection with up/down for free. But
  `selectGlyph` calls `glyphFocusRequest = UUID()` which moves focus to the
  glyph canvas, so the second arrow press goes to the canvas, not the list.
  Split "select" from "focus": from the sidebar, select without stealing focus;
  from the canvas, ← → keep stepping. M for getting this right.
- Selection color: the system accent highlight (see idea 12 and hard problem 1).
  Selection should not cause mode jumps while merely arrowing in Text mode;
  today clicking a character opens Glyph. Three-column's sidebar in Text mode
  highlights differing characters in the text and clicking jumps to Glyph. Need
  an explicit action (Return or double-click) versus selection; design decision.
- macOS 26: with `.searchable`, `placement: .sidebar` is "fixed to the toolbar"
  (`macos-26-release-notes`), so the search field cannot sit at the top of the
  list as drawn in the three-column render on 26; it goes to the toolbar.
- HIG: a sidebar is for navigation between areas (hig.md section 1); a ranked
  list is closer to a content list. It works but is not what the sidebar
  component is documented for.

(b) Horizontal line of type (one-sheet, free, and triptych's `Differences` on
glyph view).

- Existing mechanism (`ScrollViewReader` + `ScrollView(.horizontal)` +
  `LazyHStack`, `scrollTo` on selection) restyled: borderless buttons, glyph
  plus 3 pt bar, selected underline. The scroll area id
  `Differences strip scroll area` stays.
- Arrow keys: make the strip a single focus stop with `.focusable()` +
  `.onKeyPress(.leftArrow/.rightArrow)` (macOS 14, verified
  `apple-docs://swiftui/view/onkeypress(_:action:)`, "only while the view has
  focus"), or reuse the canvas's key handling (already there). Full Keyboard
  Access and VoiceOver: each cell is a labeled button "Inspect U+0040 COMMERCIAL
  AT" with the selected trait (code).
- Glyph alignment on a common baseline across cells: the overlay is drawn by the
  custom view, so the baseline is the view's own; do not rely on `Text`
  baselines.
- Unverified: whether a horizontal SwiftUI `ScrollView` scrolls with a plain
  vertical mouse wheel on macOS. If not, mouse users need Shift-scroll; arrow
  keys and the strip's auto-scroll mitigate.
- Cost: S-M, smallest of the three; it is today's design made quieter.

(c) Centre column (triptych).

- A vertical `List(.plain)` or `ScrollView` + `LazyVStack` between A and B
  columns in an `HStack`; 34 pt rows, 24 pt overlay, 3 pt bar. Same arrow-key
  story as (a), without a system selection color if it is a plain scroll view
  with custom highlight (so no accent leak). Column widths change between
  Text/Languages (576/288/576) and Glyph (480/480/480); animating that reflows
  the `NSTextView` columns every frame; expect jank. Prefer a crossfade or a
  snap; a cheap `Layout` or a `GeometryReader` is enough for static widths. M.

Evidence: code (`WorkbenchView.differences`, `selectGlyph`, `navigate`);
`platform-api.md` (searchable macOS 26 note, onKeyPress); hig.md (list as
content pane). Size: (a) M, (b) S-M, (c) M. Risk: focus handoff and selection
semantics.

## 6. Glyph view: one baseline rule across the window, a hero overlay, zoom and pan

How to build.

- Keep the AppKit stack (`GlyphScrollView` with `allowsMagnification`,
  `GlyphDrawingView`, wheel/pinch/smart-magnify). It already preserves the fixed
  baseline when stepping characters (AGENTS.md rule). Do not re-implement
  magnification in SwiftUI; `MagnifyGesture` (macOS 14) lacks pointer-anchored
  zoom and scroll-view integration.
- Three figures (solo A, hero overlay, solo B) on one baseline: one drawing view
  spanning the stage, with three figure origins sharing `baselineY` in the
  unmagnified coordinate space. Draw each in em units with `unitsPerEm`
  normalization (1000 vs 2048); hero scale is a layout constant. The overlay's
  red/blue/black compositing and outline are existing (`GlyphOverlay`,
  `GlyphOverlayOutline`). Metrics under each figure move into a SwiftUI `Grid`;
  metrics "at the guides they measure" (triptych: LSB/advance/RSB placed under
  the guide lines) need guide x positions out of the drawing view: expose them
  through a callback or compute from the same geometry (a pure function in
  TypefaceCore, tested).
- The rule that crosses the whole window (one-sheet, free, triptych render
  full-bleed black rule from x=0 to x=2000): inside the scroll view it already
  spans the stage; to span margin labels at the far left ("x-height", "baseline"
  at x=22 in triptych) and the area beyond the stage, make the scroll view
  full-bleed (zero horizontal padding) and draw labels as a non-magnified
  overlay (SwiftUI `overlay` positioned from a `baselineY` published by the
  view). The line must remain 1 px at every magnification: stroke width
  `1/magnification`, or draw it in a layer outside the magnified clip view.
- Three-column draws the rule only across the detail pane (cannot pass under
  sidebar/inspector); nothing special.
- Zoom UI: `- 100% +` stepper or pop-up with 100/200/400/800 (existing zoom
  model, current slider replaced); View menu Command-+/-/0 in
  `WorkbenchCommands`.
- Pan: existing `pan(by:)`; "zoom and pan apply to the whole stage and stay
  fixed between characters" (one-sheet) is already how the scroll view behaves
  when only the document changes, but must be verified when the selected glyph
  changes (the existing `GlyphZoomTests`/`GlyphNavigationTests` cover part).

macOS 15 vs 26/27: on 26 the toolbar/scroll-edge effect interacts with a
full-bleed `NSScrollView` going under the toolbar; the baseline rule is
mid-window, so the edge effect only affects top glyph area for large zoom.
NSScrollView itself is unchanged. Size: M (restructure drawing geometry +
overlay labels + metrics views), L if the three figures must also zoom
independently. Risk: the baseline staying pixel-aligned across three figures
with different unitsPerEm and a hero scale, and the HTML mock's labels at far
left over a magnified, scrolling document. Evidence: code
`GlyphScrollView.swift`, `GlyphComparisonView.swift`; the three glyph renders
(three-column hero 100% only inside the detail pane; triptych/one-sheet/free
window-wide rule).

## 7. One A/B settings table: joined slider when linked, split when unlinked; union typography table with per-font checkboxes

How to build.

- Layout: `Grid`/`GridRow` (macOS 13) with A column, label column, B column, so
  values line up row-wise; labels centred or in the margin per design.
- Joined vs split slider. There is no two-thumb or "joined track" control in
  SwiftUI. The joined slider is one `Slider` whose binding reads/writes A's
  value through the model
  (`model.edit { $0.set(property, to:, side: .a ...) }`); the model already
  propagates to B via `link` ratios/offsets (`calibrate()`). Unlinked: two
  sliders. The "morph" between the two is a conditional layout swap; it cannot
  animate as one track. Size/leading/tracking ranges differ between A and B
  (clamps); the joined slider's range must be the intersection of the achievable
  range on both sides; a model function with tests.
- Fields: `TextField(value:format:)` (macOS 12), `.textFieldStyle(.plain)` with
  an underline rule (idea 11). Field + slider + stepper pairing is HIG-endorsed
  (sliders page, hig.md).
- Auto leading etc.: checkbox per side (`Toggle(.checkbox)`), same as today.
- Union typography table. New model, not a new view: build rows as the union of
  A's and B's features keyed by `FontFeature.id` (OpenType tag), each row
  holding `a: Feature?`, `b: Feature?` with `nil` rendered as "-". Today
  `FontTypography` is per side. Each row: label + tag (monospaced), A
  checkbox/menu, B checkbox/menu, and per-side live previews ("AV -> AV") from
  `FeaturePreviewModel` (exists). Two previews per row times 30-60 rows:
  lazy-render and cache, otherwise the table is expensive; unverified cost.
  Non-boolean features (Character Alternatives, Number Spacing) are `Picker`
  menus per side. Group headers = `DisclosureGroup` (macOS 11);
  `collapsedGroups` state goes in the model.
- Typography is never linked (AGENTS.md: "independent typography"), so no join
  logic; "Preserve calibrated links" still holds for appearance.
- Reset glyph column: see idea 13.

macOS 15 vs 26/27: 26 re-skins `Slider` (glass knob when dragging) and gives
`SliderTick` (26) for ticks; `.formStyle(.grouped)` is more compact in sidebars
on 26 (`macos-26-release-notes`). 27 beta: "On macOS, the `Slider`
implementation no longer uses `NSSlider`" (verified in `platform-api.md`). The
accessibility role and any automation that expects `NSSlider` may change (idea
14). Size: L (union model M, views M, tests). Risk: slider look cannot match the
mock (thin track, small round knob) except by luck; the track cannot be
restyled. Replacing it with a fully custom slider is possible but accessibility
(adjustable trait, increments, VoiceOver) then must be rebuilt. Evidence: code
`FontInspector.numericControl`, `FontTypography.swift`,
`FeaturePreviewModel.swift`; three-column and free renders (`detail.png`);
hig.md sliders/disclosure.

## 8. A settings band that folds open between toolbar and content versus the system inspector

Used by: one-sheet (fold), triptych (register), free (a smaller specification
always visible; inspector for features).

How to build the band.

- A plain `VStack`: `[band][content]`. The band is a normal view whose height
  animates from 0; hidden state keeps the view in the tree with
  `.frame(height: 0).clipped().disabled().accessibilityHidden(true)` like
  `InspectorPanel`, so disclosure and scroll state persist for free. The cap
  ("as tall as its rows up to half the content height, then scrolls") needs the
  content's measured height (a `PreferenceKey`) and the window height; do not
  use `GeometryReader` around the whole body.
- Under the 26 toolbar, put it in the top safe area
  (`safeAreaInset(edge: .top)`, macOS 12) so the scroll edge effect sees a bar;
  `safeAreaBar` is 26-only (verified
  `apple-docs://swiftui/scrolledgeeffectstyle`). Under 15 the band sits below
  the titlebar.
- Toggle: a toolbar button (a toggle button; HIG says avoid checkboxes and
  switches in toolbars) bound to state, plus View menu command with a shortcut.
- Match mode lives in the same band (idea 9).

Trade-offs against `.inspector`.

- Better: full-width rows put A, label, B on one line and next to the sample
  (the idea's point); no leading/trailing edge restriction; deterministic state
  retention; no width negotiation; works the same on 15, 26, 27.
- Worse: pushes the specimen down, so the `NSTextView` columns reflow while
  animating (an `NSTextView` re-layout of a long sample per frame is probably
  acceptable for a 3-4 paragraph sample but is unverified; if it janks, snap
  open or animate opacity and offset rather than height). Loses restoration of
  presentation state and the automatic collapse behavior. Loses the 26
  floating-glass pane treatment that the inspector would get. The HIG prefers
  panes or panels for repeated adjust-and-observe work (hig.md panels/sheets): a
  band is closest to a panel; it is not a sheet, so acceptable.
- Vertical space is the scarce dimension (HIG: avoid critical controls at the
  bottom; the designs put it on top, good). 236 pt of 900 at open.
- Two copies of a control (masthead size field and fold size row, one-sheet) are
  fine functionally but require distinct accessibility identifiers (idea 14).

Size: band M; inspector S (+ state work, idea 2). Risk: reflow cost and
animation; tall-fold sizing. Evidence: `InspectorPanel.swift`; one-sheet and
triptych specs; `platform-api.md` section 4 (safeAreaBar 26).

## 9. Match as a live mode instead of a sheet

How to build.

- Keep `FontFitModel` unchanged (engine). Add a `matching` state at the window
  level. While matching, the canvas renders `comparison` with B replaced by
  `fit.result?.proposed ?? b` (a derived `displayedComparison`), so the
  specimen, the overlay, and the metrics show the proposal live;
  `model.comparison` stays untouched until Apply (this preserves the existing
  guarantee `matchingPreviewKeepsComparisonUnchangedUntilApply`,
  `WorkbenchInteractionTests`). Cancel drops the preview; Apply calls
  `fit.apply(to:undoManager:)` as now.
- UI: a "Match bar" (free; replaces the index line), the inspector in match mode
  (three-column), or rows of B with `Optimize` buttons in the band (one-sheet,
  triptych). In each case the per-row "before -> after" values (`option(...)`
  today) become row accessory views. The disabled-commands gate
  (`focusedSceneValue(\.workbenchActions, showMatch || showEditor ? nil : commands)`)
  is reused so Undo/Swap do not fire mid-match.
- Cost issue: the ranking (`RankingModel.update(comparison)`) recomputes when
  the comparison changes. If the derived B feeds the ranking, each accepted
  proposal triggers a full recompute; keep ranking bound to the committed
  comparison and hide the strip while matching (free hides it).
- Stopping on window close/mode change: `fit.stop()` as in `.onDisappear` today.

What changes for the fuzzer: today a sheet is the signal (`Cancel matching`);
the fuzzer's window-scope and "which sheet is open" rules in `UIFuzzSupport`
(`WindowScope`, `MutationState` strings such as
`Reference A specimen scroll area`, `Match options scroll area`) must learn a
non-sheet mode (idea 14).

macOS 15 vs 26/27: none. Size: M-L (mostly UI placement; the engine and the
preview logic exist). Risk: derived-comparison plumbing touches every consumer
of `comparison.b`; mid-match edits to other controls (decide: lock them);
fuzzer/test updates. Evidence: code `MatchSheet.swift` (`proposal(b)`,
`request`), `WorkbenchView` (`sheet`, `focusedSceneValue`); AGENTS.md
(sheet-identifying controls); HIG sheets/panels ("panel instead of sheet if
people repeatedly provide input and observe results").

## 10. In-place sample text editing

How to build.

- The specimen is already an `NSTextView`. Add an editing state on the A
  column's view: `isEditable = true`, `isRichText = false`, make it first
  responder; `NSTextViewDelegate.textDidChange` publishes the string to
  `comparison.customText` (and sets `sample = .custom`); B's view re-renders
  from the model. End on Escape or Command-Return; one Undo group named "Edit
  sample" (the window's `UndoManager` is the one `WindowUndoManager` provides;
  NSTextView registers typing against its window's undo manager, so coalescing
  typing with the model's `edit(...)` grouping is the open question).
- The hard parts: (1) `SpecimenText.updateNSView` presently rebuilds content
  from `comparison.text` plus highlight spans; during editing it must not
  replace the storage (selection and IME marked text would reset). Guard: skip
  the rewrite while `hasMarkedText()` or while the view is the first responder
  and `string == model text`; apply the red/blue highlight spans after editing
  ends (show black ink while editing). (2) The two columns are laid out
  independently, with synchronized scroll (`SpecimenScrollPosition`); typing in
  A must scroll-follow caret and keep B in step. (3) The caret and selection
  colors must be neutral (idea 1). (4) Tooltips and click-to-inspect behaviors
  in the view (it is `NSViewToolTipOwner`, handles clicks to select glyphs) must
  be off while editing.
- Fallback named in the one-sheet spec: a popover editor anchored to "Edit
  text". Today it is a sheet with a `TextEditor` (id `Custom specimen text`),
  which the fuzzer also uses as a sheet signal.

macOS 15 vs 26/27: TextKit 1 is used (`NSLayoutManager`), so behavior should be
the same across versions; input methods and Writing Tools on 15+ add marked-text
paths worth testing (unverified). Size: M-L. Risk: high relative to size: IME,
undo, caret management, rewrite-while-editing. It is also the idea most likely
to have a sharp edge bug in the wild. Evidence: code `SpecimenText.swift`
(`NSViewRepresentable`, `SpecimenNSTextView`), `WorkbenchView.editor`.

## 11. Borderless, typeset-looking controls that remain real accessible controls

How to build.

- Real controls, restyled, never `onTapGesture` on `Text`: `Button` +
  `.buttonStyle(.plain/.borderless)`; `Picker(.menu)` +
  `.menuStyle(.borderlessButton)` (verified); `TextField` +
  `.textFieldStyle(.plain)` (macOS 10.15, verified
  `apple-docs://swiftui/textfieldstyle/plain`) with an underline `Rectangle` of
  `1/displayScale` and `.contentShape(Rectangle())`; `Toggle(.checkbox)` stays a
  checkbox (the designs use checkboxes; HIG prefers them for hierarchies). Put
  each style in one `ButtonStyle`/`MenuStyle` so the look is set once.
- Hit targets: HIG macOS minimum 20x20 pt (28 default) and about 24 pt padding
  for bezel-less controls (hig.md section 4). Underlined numbers like "22" are
  about 14 pt tall; pad the content shape.
- Affordance: `.pointerStyle(.link)` (macOS 15.0, verified
  `apple-docs://swiftui/view/pointerstyle(_:)`) or `.onHover` feedback so
  borderless text reads as clickable; for text-input fields use
  `.pointerStyle(.horizontalText)` where available (unverified symbol).
- Focus: keep the system focus ring on these (do not `focusEffectDisabled`) or
  draw a replacement from `@FocusState`; see idea 1.
- Color is not the only channel: the legend must be text ("Only A", "Only B",
  "Shared") in each design (HIG color: "Avoid relying solely on color";
  `accessibilityDifferentiateWithoutColor`, macOS 10.15,
  `apple-docs://swiftui/environmentvalues/accessibilitydifferentiatewithoutcolor`,
  cited in the one-sheet spec).
- Chrome type: system font (HIG: SF; hig.md typography). The website's Helvetica
  Neue in a font-comparison tool would put the brand font in competition with
  the specimen; that is a design call, not a build limit.
- macOS 26: `.plain`/`.borderless` content-layer controls do not get glass;
  toolbar items do. In the toolbar use standard components (HIG: prefer system
  symbols without borders).

macOS 15 vs 26/27: pointer API requires 15 (fine at the deployment target). Menu
item symbols hidden by default from 26 (use `.labelStyle(.titleAndIcon)` where
an icon matters; `macos-27-release-notes`). Size: M. Risk: low technically; the
cost is the number of controls and VoiceOver audit; reading "22" as a field
needs a label ("Font A size"). Evidence: `platform-api.md` section 5; hig.md;
code `FontInspector.numericControl` (current identifiers/labels).

## 12. Languages as a sortable Table with two character sheets

How to build.

- `Table(rows, selection: $selection, sortOrder: $sort)` (macOS 12,
  `apple-docs://swiftui/tablecolumncontent`) with columns Language (name),
  Speakers (sortable `KeyPathComparator`), A, B coverage dots (comparator on
  coverage state). Default sort speakers descending (free) or name (three-column
  list). `LanguageBrowserModel` supplies `rows`; add sort to the model so it is
  covered by tests. Column resizing and header click-to-sort are free (HIG
  lists-and-tables).
- Coverage glyphs: dot or ring plus an accessibility label "complete/incomplete
  in A"; not color alone.
- Detail: the selected language's sheet in A and in B (stacked in free; side by
  side in three-column and triptych), a coverage table (category, A, B, Missing)
  in free via `Grid`.
- Character sheets: `LanguageBrowserView` already draws categories with
  checkboxes and counts. Triptych draws a fixed grid with missing characters as
  outlined empty cells. Implement each category as one drawn view (Core Text /
  `Canvas` / `NSView`) with a single accessibility element whose label
  summarizes ("56 of 56 present"), not one SwiftUI view per character: CJK and
  Arabic sheets run to thousands, which makes the accessibility tree huge and
  slows the UI fuzzer's tree walks (`AXDiscovery`).
- Selection color: the `Table` row highlight is the system accent (blue by
  default), which collides with "blue = ink only in B" in the same window.
  Fixes: custom row view in an `NSTableView` wrapper, or `Table` without
  selection highlight plus our own row background; both are unverified for
  SwiftUI `Table` (HIG color: "Avoid using the same color to mean different
  things").

macOS 15 vs 26/27: `alternatingRowBackgrounds` is macOS 14 (from memory,
unverified); on 26 `Table` row styling changes slightly. Size: M (S if selection
color is accepted as is). Risk: selection color; Table header cannot be restyled
to the site's small-caps look; large sheets and AX tree size. Evidence: code
`LanguageBrowserView.swift` (`languageList`, `filters`, ids
`Language search field`, `Language speaker slider`, ...); `platform-api.md`
section 1 (Table); free and one-sheet language renders.

## 13. Reset buttons shown only for changed values

How to build. Conditional views driven by pure functions of the model:
`if value != defaultValue { ResetButton(...) }`. The "changed" tests already
exist as `canResetAppearance` (compare a reset copy) and
`value == defaultValue`; make them per property and per section in the model
(tested in the package target, so cheap to hold at 100%). Section reset in the
header only when any child changed. Reserve the slot's width so rows do not
shift (use `.hidden()`-style reservation, with the button also out of the
accessibility tree; verify that `.hidden()` removes the element from the AX
tree, unverified).

- Discoverability for non-sighted users: expose
  `accessibilityValue("changed from default")` on the setting row; the button
  itself is then found only when relevant.
- Existing `symbolEffect(.wiggle)` (macOS 15) keeps working.

macOS 15 vs 26/27: none. Size: S. Risk: the fuzzer. Today every reset button
exists and is disabled when at default (code:
`.disabled(value == defaultValue)`; ids `Font A Reset size` etc.); recorded
traces replay those names. An absent control is a different outcome from a
disabled control, so replays and any exploration state that targets reset
buttons see resolution failures until the corpus is regenerated or
`ResolutionFailure`/`SkipLedger` rules treat absence as a skip (idea 14).
Evidence: code `ResetButton.swift`, `FontInspector.numericControl`; all four
specs.

## 14. The 100% coverage gate and the UI fuzzer contract

Gate facts (AGENTS.md, `scripts/coverage.sh`, read): `make coverage` merges
SwiftPM and Xcode app-hosted profdata, requires 100% line and 100% region for
every file under `Sources/TypefaceCore`, `Sources/TypefaceOff`,
`Sources/UIFuzzSupport` (excluding only `/(Tests|.build)/`), and rejects clamped
counts. `Sources/UIFuzz` (including `AXDiscovery.swift`) is outside the gate.
Existing views carry scars from region coverage: the explicit
`State(initialValue:)` initializers "so Xcode 26's coverage does not include
unused synthesized initializers"; "Swift coverage mapping can derive negative
counts after an optional binding in the same builder"; "Counts clamped... fail
the gate".

What a rebuild means.

- Replacing about 2,600 lines of view code (`WorkbenchView` 429, `FontInspector`
  276, `FontTypography` 144, `GlyphComparisonView` 517, `LanguageBrowserView`
  425, `MatchSheet` 185, pickers) means rewriting the app-hosted tests that
  exercise them; they already drive the UI by accessibility name through
  `WorkbenchTestHost` (press, element, settle). If identifiers survive, most
  tests survive; the ones that depend on layout (finding controls by scrolling,
  sheet-based Match/editor tests) change.
- How to keep it green.
  1. Logic goes to models (`TypefaceCore`/model files) with unit tests: union
     typography rows, joined-slider range, per-setting "changed", sort order,
     match preview derivation, search routing by mode. Views become thin
     declarative shells.
  2. Few conditional regions per view; split `@ViewBuilder` bodies into small
     subviews so each `if` is reached by one test; avoid `if let` followed by
     other builder content in the same builder (known negative-count issue).
  3. No OS branches in gated files. An
     `if #available(macOS 26, *) { A } else { B }` leaves one arm uncovered on
     any single-OS coverage run, so it fails the gate. Use only APIs available
     on 15 (the design renders already come out acceptable from automatic 26
     adoption), or isolate each 26 call in one small file and ask the owner to
     change the gate (an explicit exclusion in `coverage.sh`); that is a policy
     decision, not mine. This rules out explicit `ToolbarSpacer`, `safeAreaBar`,
     `glassEffect` and the `.tabs` picker (27 beta) unless the owner decides
     otherwise.
  4. New AppKit views (baseline overlay labels, strip scroll bridge, table row
     view) need test hosts like the existing `GlyphZoomTests`; cover via
     synthetic fixtures, not user-installed fonts (AGENTS.md).
  5. Character-name search tests must use long-established characters (differing
     Unicode names across 15/26/27).
- Fuzzer contract (AGENTS.md). Identifiers: `Font A <label>` / `Font B <label>`
  from `side.fontName`; scroll areas end in `scroll area`; every identifier
  unique in a window and never equal to another element's label, title or menu
  title; do not change ids the fuzzer uses (`Shared point size`, `Glyph canvas`,
  search fields, `Font A specimen` labels, icon-only buttons' symbol names,
  `Cancel matching`, `Custom specimen text`). Rebuild consequences:
  - Duplicate controls in two places (one-sheet's masthead size field and the
    fold's Size row; free's specification row and the inspector's Appearance
    rows) would collide; give the second a distinct id (for example
    `Font A Size field` vs `Font A masthead size`) and update `UIFuzzSupport`
    name lists if it should be exercised.
  - A single joined slider while linked removes `Font B <label>` slider ids in
    that state; a recorded trace that moves `Font B Size` fails to resolve.
    Options: keep both elements in the tree and visually join them, or accept a
    corpus regeneration and teach the resolver that the id is state-dependent.
  - Reset buttons that vanish (idea 13) and settings hidden in a closed
    band/inspector change visibility rules; `VisibilityRules`,
    `ResolutionFailure`, `SkipLedger` and `MutationState` need entries.
  - Sheets: Match and Edit become non-sheet modes; `WindowScope` and the "which
    sheet is open" logic need a non-sheet signal (a stable `Cancel matching`
    button remains the simplest signal if kept in the band).
  - New element kinds: `List`/`Table` rows (`AXRow`, `AXCell`, already handled
    in `AXDiscovery`), a horizontal strip (same as today), the sidebar toggle
    (system).
  - macOS 27's `Slider` is no longer an `NSSlider`: check the AX role and the
    `AXSlider` handling in `AXDiscovery.swift` (outside the gate, so it can be
    adjusted freely) on 27.
  - Thousands of per-character accessibility elements would stress tree dumps:
    keep sheets as single elements.
- Size: L overall, but spread: most of it is test and fuzzer maintenance
  proportional to how many ids and sheets change. Three-column changes the
  fewest (inspector and sidebar content mostly preserved); triptych/one-sheet
  change the most (settings table, bands, no panes). Evidence: AGENTS.md;
  `scripts/coverage.sh`; code comments quoted above;
  `UIFuzzSupport/MutationState.swift` list of known targets;
  `Tests/TypefaceOffTests/WorkbenchInteractionTests.swift` (`WorkbenchTestHost`,
  press by name).

## Per-design summary of build effort (my judgment)

- Three-column: M-L. System split view and inspector carry most layout; sidebar
  `List` and inspector table are the new views. Biggest risks: selection color,
  1080 minimum width, sidebar material on 15, search placement on 26.
- Free ("Two Lines"): L. Two-line specification replaces both inspectors (grid
  of borderless controls), strip is today's strip, system inspector only for
  features and appearance sliders, Match bar. No sidebar. Biggest risks: search
  field results, joined fields/links, density of the specification at 1080 wide.
- One sheet: XL. Everything is bands of one grid; fold band, union table, Match
  in the fold, in-place editing, window-wide baseline. No system panes to lean
  on. Biggest risks: fold reflow, joined settings table, in-place editing.
- Triptych: XL. Everything custom, plus a symmetric grid that re-proportions
  between views and a centre spine with its own list, link text between values.
  Biggest risks: animated column grid with `NSTextView` columns, register band,
  two-copy a11y.

## Hard problems that need a prototype before committing

1. Neutral selection and focus: row selection in `List`/`Table`, text selection
   and caret in `NSTextView`, and focus rings, on 15/26/27 with the user's
   accent set to red and to blue. Decide whether to accept accent leaks or build
   custom row/selection drawing.
2. Paper-white window under the 15 titlebar and the 26 glass toolbar; sidebar
   material on 15 versus the "one sheet" promise; Increase Contrast and Reduce
   Transparency.
3. Space budget for sidebar + inspector at 1080 wide (three-column);
   auto-collapse versus minimum width.
4. Toolbar: `.principal` centring, four items under the three-group guidance,
   and one `.searchable` field that serves Find Character (rich results) and
   language filtering.
5. Window-wide baseline with three figures, unitsPerEm normalization, labels
   outside the magnified region, and the same baseline while stepping.
6. In-place editing in the specimen `NSTextView`: IME, undo coalescing with the
   model, mirror B, no storage rewrite while typing.
7. Match live mode: derived comparison versus the ranking cost, locked controls
   while matching, and the fuzzer's loss of the sheet signal.
8. Settings band push-down: reflow cost of the two `NSTextView` columns while
   animating; the half-height cap and scrolling.
9. Joined slider: intersection ranges under clamps, accessibility of one slider
   that moves two fonts, and the fuzzer-id consequence.
10. Union typography table: per-row dual previews performance and a clear model
    for features present in only one font.
11. Coverage with OS-specific APIs: decide the policy (no `#available` in gated
    files versus a documented exclusion) before design adopts 26-only calls;
    confirm app-hosted tests on 15, 26 and 27 produce the same coverage.
12. 27 beta behaviors: `Slider` reimplementation and missing sidebar-toggle bug.
