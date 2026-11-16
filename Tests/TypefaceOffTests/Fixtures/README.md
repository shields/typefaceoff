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
