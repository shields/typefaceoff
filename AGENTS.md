# Project guidelines

Follow `../right-answers/README.md`, `../right-answers/swift.md`, and
`../right-answers/ci.md` for shared conventions.

Use `make build`, `make test`, `make coverage`, `make lint`, and `make fmt`.
`project.yml` is the source of truth for the generated Xcode project and app
metadata. The Swift package owns the font engine and its tests.

Preserve calibrated links, independent typography, native-unit metrics, and
fixed-baseline glyph navigation when changing the app. Missing fonts or
characters must be visible; never compare a silent fallback.
