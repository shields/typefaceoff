`OpticalSize.ttf` is a synthetic font with one rectangular glyph and `opsz` and
`wdth` axes, defined by `OpticalSize.ttx`. Regenerate it from the repository
root with:

```sh
uv run --frozen fonttools ttx --no-recalc-timestamp -o Tests/TypefaceOffTests/Fixtures/OpticalSize.ttf Tests/TypefaceOffTests/Fixtures/OpticalSize.ttx
```
