# AXPress failure with NSTextView accessibility setters

This standalone sample isolates the reported failure: an enabled SwiftUI button
opens its sheet while `AXUIElementPerformAction` reports `kAXErrorFailure`
(`-25200`). The app uses AppKit and SwiftUI, and has no third-party
dependencies. The roughly 40-line `App.swift` is the UI reproducer;
`Press.swift` is the separate accessibility client that observes the return code
and the sheet independently.

The reduced sample builds with Swift 6 and warnings treated as errors. Its fresh
live verification is pending because the desktop is locked. The accompanying
report distinguishes the earlier verified experiments from this reduction.

From this directory, with Xcode selected:

```sh
make build
make reproduce
```

Enable Accessibility permission for the terminal running the client and keep the
desktop unlocked. The client fails with an explicit error if either prerequisite
is missing. It terminates each app it launches, including when a check fails. It
does not move the mouse, synthesize keyboard input, or activate the app.

`make reproduce` launches three app processes sequentially and performs ten open
and close cycles in each:

| Mode         | Setter called in the sheet               |
| ------------ | ---------------------------------------- |
| `label`      | `setAccessibilityLabel("Specimen")`      |
| `identifier` | `setAccessibilityIdentifier("Specimen")` |
| `none`       | Neither setter                           |

For an individual run:

```sh
.build/press .build/AXPressRepro.app/Contents/MacOS/AXPressRepro label
```

Replace `label` with `identifier` or `none` to run a control. Each row reports
the raw AX return code, verifies that the opener is enabled, and confirms the
presence of the sheet's Cancel button. The client waits for that button to leave
the tree before pressing the opener again. The final summary gives the number of
failed return codes and opened sheets.

A successful first press can occur even in an affected run. Look at the repeated
presses; the `none` variant should return zero throughout. The client reports
the observed results without requiring that an OS version exhibit the bug.

From the Typeface/Off repository root, the equivalent commands are:

```sh
make axpress-repro-build
make axpress-repro
```

The repository targets put build products in `.build/apple-axpress-repro`.
`make lint` and `make fmt` in this directory check and format the standalone
Swift sources; repository-wide formatting and lint also cover them.
