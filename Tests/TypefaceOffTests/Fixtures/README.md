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

`OpticalSize.ttf` is a synthetic font with one rectangular glyph and `opsz` and
`wdth` axes, defined by `OpticalSize.ttx`. Regenerate it from the repository
root with:

```sh
uv run --frozen fonttools ttx --no-recalc-timestamp -o Tests/TypefaceOffTests/Fixtures/OpticalSize.ttf Tests/TypefaceOffTests/Fixtures/OpticalSize.ttx
```

`Weight.ttf` uses the same rectangular glyph with a single `wght` axis and
standard and discretionary ligature substitutions to exercise Match's axis and
feature controls. Regenerate it with:

```sh
uv run --frozen fonttools ttx --no-recalc-timestamp -o Tests/TypefaceOffTests/Fixtures/Weight.ttf Tests/TypefaceOffTests/Fixtures/Weight.ttx
```
