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

# Language coverage

The Languages view compares the selected fonts against
[Hyperglot 0.8.1](https://github.com/rosettatype/hyperglot)'s orthography
inventories. Open it with ⌘3 or **View → Languages view**. The inspectors remain
available. Missing characters open the existing Glyph view.

## Catalog and display filters

The app ships 705 language records and 757 orthographies. Importing retains
**preliminary** and **verified** data and **primary** and **historical**
orthographies. It excludes 76 records with lower data confidence and 7 records
without a retained orthography. Secondary orthographies, transliterations, and
draft and todo records are outside this catalog.

The default minimum is **8,300,000 speakers**, the fixed 0.1% threshold chosen
using an 8.3 billion global population. It does not track world population. The
default **Show historical** setting is off. Together these filters show **108
languages and 119 primary orthographies**. Turning historical on at the same
threshold shows **130 languages and 150 orthographies**. Historical language
records bypass the speaker threshold when enabled. Historical orthographies of
living languages are also hidden by default.

The speaker slider is logarithmic, with an **All** position before the numeric
range. Numeric thresholds begin at 100 speakers and end at the largest count in
the catalog, currently **920M** for Mandarin Chinese (2017). **100M** is the
last power-of-ten tick. No catalog record has a billion speakers. Exact entry
accepts k and M suffixes and clamps to the slider range. These are Hyperglot's
recorded estimates with their original dates; they are not the total-speaker
figures used by the character-frequency corpus.

Search matches language names, autonyms, ISO codes, and script names and codes.
Search respects the display filters and reports matches hidden by the speaker or
historical filters. **Clear filters** chooses All speakers, enables historical
records, and clears the coverage restriction, retaining the query. The coverage
filter offers All, Both, A only, B only, and Neither with two fonts, or All,
Covered, and Incomplete with one font. Lists remain alphabetic.

Search, filters, selection, list and detail scroll positions, and expanded
details belong to each window and survive switching views. They are not
persisted and do not consume Undo steps.

## Coverage policy

The importer uses Hyperglot's own inheritance and inventory parser. Encoded
requirements follow its base policy with optional marks and decomposition
disabled. The app checks those requirements against the configured font's cmap.
It separately renders supplied combining sequences with Core Text and rejects
fallback runs and glyph zero. Decorative dotted circles in source mark
inventories are not coverage requirements. Requirements and cache identities
retain exact Unicode scalars; canonical String equality cannot merge them.

Base coverage establishes completeness. Auxiliary characters, numerals,
punctuation, and currency are reported separately. Independent primary
orthographies are alternatives: one complete orthography suffices. Every
orthography marked `preferred_as_group` must be complete to establish coverage
through that group. A historical orthography cannot establish current primary
coverage for a living language. Details name the scripts establishing coverage
and distinguish Checking, Complete, Incomplete, and Font unavailable.

Character coverage does not assess joining behavior, mark placement, or visual
quality. The view supplies verified font previews and system-font metadata so
missing coverage cannot become a silent fallback comparison. Font selection
remains independent of language coverage.

## Character sheets

**Use as specimen** transfers the selected orthography's inventories to custom
sample text and opens Text view. Base is selected initially; Auxiliary,
Numerals, Punctuation, and Currency are optional. Tokens preserve the source
order and scalar sequences, separated by spaces, with blank lines between
categories. The sheet contains no inserted English headings and includes
unsupported characters and the complete chosen inventories. It is a character
sheet, not a natural reading passage.

The transfer is one **Use language specimen** Undo edit. It does not alter font
selection, typography, calibrated links, or appearance. Multi-grapheme source
tokens remain whole in the sheet; missing-character controls open each
individual grapheme in Glyph view.

## Generation and verification

The committed JSON and upstream Apache license are package resources. NOTICE
credits Rosetta Type/Research and the Hyperglot contributors. Normal app builds
and use are offline and require no Python. Developer tools use uv, Python 3.15
or later, and the locked Hyperglot 0.8.1 dependency:

```sh
make languages
make languages-check
make test-languages
```

Edit `scripts/language_data.py`, not the generated table. Generation is
deterministic, expands upstream inheritance, preserves speaker dates,
confidence, sources, notes, contributors, and reviewers, and copies the upstream
license verbatim. Tests verify the release counts, exclusions, inventories,
inheritance, grouped orthographies, and deterministic regeneration. CI checks
regeneration.

The immutable catalog loads lazily off the main actor. Coverage prioritizes the
selected and initially visible rows, then fills the complete catalog. Shared
requirements are probed once per retained configuration. The actor caches four
recent configurations, keyed by face, variation axes, features, and point size;
tracking and leading do not affect character coverage. Filter edits reuse these
scores. Requests cancel obsolete work and reject stale results. Non-cancellation
errors appear in the view, and corrupt bundled resources fail fast.

Swift tests cover the policies, real-font fallback rejection, scalar identity,
caching, cancellation, window state, specimen Undo, accessibility controls, and
fuzzer mode repair. App tests run in the existing macOS 15, 26, and 27 CI
matrix.
