# Mockup parity

The native workbench follows the interactions in
[the browser study](../mockups/README.md). Use `make review` to regenerate the
native reference states in `.build/review`. The text and glyph captures cover
1440 × 900 and 1280 × 800 content areas. Native titlebars add the standard macOS
window controls and inspector toggles.

## Interaction coverage

| Area              | Native behavior                                                                                                                                                                                                          | Verification                                                                                                                     |
| ----------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | -------------------------------------------------------------------------------------------------------------------------------- |
| Workbench         | Text/glyph modes, sample selection, custom-text editor, shared/Mixed size, Undo, Swap, Match, and both inspector toggles.                                                                                                | `WorkbenchView`; text and glyph review captures at both reference sizes.                                                         |
| Inspector state   | Collapsing an inspector retains its scroll position and disclosure state; hidden controls do not receive clicks or accessibility focus.                                                                                  | `InspectorTests`; `InspectorPanel`.                                                                                              |
| Reading           | All four supplied samples, heading/body/attribution hierarchy, literal custom text, colored characters, and proportional scrolling between sides. Reading position survives glyph inspection and resets for new samples. | `DocumentTests`, `SpecimenScrollTests`; poetry, alphabet, numerals, attribution, and single-text captures.                       |
| Appearance        | Initially locked; size ratios and weight/tracking/shared-axis offsets work in both directions and survive clamping. Replacing families, swapping, matching, and relocking recalibrate the pair.                          | `ComparisonTests`, including variable weight and optical-size calibration.                                                       |
| Reset             | Appearance Reset restores regular styles, actual axis defaults, 22 pt, and zero tracking. It follows the lock and preserves typography. Individual numeric resets remain linked; Typography Reset affects one side.      | `Comparison.resetAppearance`, `FontInspector`; reset tests cover either side, locked/unlocked, variable axes, and missing fonts. |
| Typography        | Independent controls, grouped disclosures, automatic shaping labels, real character variants/options, and before/after examples.                                                                                         | `FontInspector`, `FontPreviewText`; shaping and preview tests; variable-font capture.                                            |
| Single font       | Selecting None removes B and the difference strip, expands A, and disables Match/Swap. Reselecting the removed family restores B's complete configuration.                                                               | `singleFontRestoresCompleteConfiguration`; single and single-text captures.                                                      |
| Ranking           | Shared printable ASCII plus sample graphemes; positive top-eight highlights for each enabled metric; independent Shape/Spacing and their union; combined ranking when both are off; cancellable calculations.            | `DifferenceTests`, `RenderingTests`, and `RankingModel`; all four highlight combinations are covered.                            |
| Glyphs            | Three views with red/blue/shared overlap, always-visible baseline and x-height guides, spacing origins, Unicode descriptions, native-unit/em metrics, and direct grapheme entry.                                         | `GlyphComparisonView`, native font-table metric tests, Unicode tests; glyph and spacing captures.                                |
| Navigation        | Character clicks and arrow navigation preserve the canvas frame, scale, and baseline. Text fields retain their arrow-key editing. Long Unicode names have full tooltips.                                                 | `GlyphNavigationTests` sends native key events and checks eleven varied characters in comparison and single-font modes.          |
| Missing data      | Specimens identify each unavailable grapheme by code point and report the distinct count. Missing fonts retain their requested names without displaying fallback metadata. Matching requires two installed fonts.        | Missing-font/character and matching tests; missing-characters and missing-font captures.                                         |
| Tooltips          | Specimen characters expose Unicode identity and enabled difference reasons; strip characters expose identity, rank, and scores. Tooltips preserve shaping runs and ligatures.                                            | `SpecimenTooltipTests`; `WorkbenchView` strip labels.                                                                            |
| Match and history | Optional suggestions appear before selection; previews do not mutate the document; Cancel discards them; Apply is one undoable edit. Browsing does not consume Undo steps.                                               | `Matching`, `MatchSheet`, `DocumentTests`; match capture.                                                                        |
| Documents         | Standard macOS documents save settings, custom text, and inspection state without embedding font files.                                                                                                                  | Versioned round-trip, validation, and snapshot tests; `project.yml` document declarations.                                       |

## Deliberate native improvements

- **Point sizes use macOS points.** The browser converts a CSS point to 4/3 CSS
  pixels. Repeating that conversion in AppKit would make a displayed 22 pt font
  render at 29⅓ pt. Native text wrapping consequently differs from the browser
  screenshots while size controls and measurements remain truthful.
- **Controls remain native.** Searchable installed-font menus, real AAT selector
  names/options, keyboard focus, standard file dialogs, and Undo/Redo follow
  macOS conventions. The study's pair selector above the simulated window is a
  demo switcher; the native inspectors select arbitrary installed families.
- **Glyphs use the available canvas.** The larger native magnification makes
  detail easier to inspect. A shared envelope fixes the scale across glyphs,
  with reserved space for accents and descenders.
- **Matching uses measured data.** Numeric weight matching replaces the demo's
  arbitrary 95% variable-weight suggestion. Tracking measures shaped text,
  including ligatures. These remain geometric/numeric heuristics, and the Match
  sheet explains their limits.
- **Undo preserves the current inspection.** Undoing a font adjustment keeps the
  selected glyph, mode, and highlight choices so the result can be compared
  immediately. Inspecting characters also preserves Redo.
- **Previews show actual substitutions.** The contextual-alternate example uses
  ASCII `->`, allowing a font such as Inter to demonstrate its arrow
  substitution. Unsupported preview characters are explicitly labeled.

Font importing, multilingual specimen design, perceptual similarity, and
contextual run-level difference ranking remain the roadmap ideas identified in
the browser study. The current comparison ranks isolated grapheme clusters.

## Reproduce the checks

```sh
make build
make coverage
make lint
make review
```

`make coverage` includes `make test`, covering both native suites and the
browser ranking math. Native UI tests and `make review` need macOS desktop
access. Install Inter Variable to run its optional axis and character-variant
tests.
