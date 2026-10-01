# AXPress returns kAXErrorFailure when a SwiftUI sheet sets NSTextView accessibility metadata

Submitted as **FB25013978**.

Suggested Feedback Assistant topic: Developer Technologies & SDKs, macOS, AppKit
accessibility. SwiftUI is involved in presenting the sheet.

## Summary

`AXUIElementPerformAction(button, kAXPressAction)` returns `kAXErrorFailure`
(`-25200`) even though an enabled SwiftUI button's action runs and opens its
sheet. The trigger is a public `setAccessibilityLabel` or
`setAccessibilityIdentifier` call on an `NSTextView` created in the sheet's
`NSViewRepresentable.makeNSView`.

The attached app uses only AppKit and SwiftUI. Its main window contains one
button. Its sheet contains one text view and a Cancel button. The attached
client launches the app, presses and dismisses the sheet ten times through the
public accessibility API, and prints each return code and whether the sheet
opened. It checks that the opener is enabled and waits for the sheet to
disappear before the next press.

## Environment

| Component    | Tested version                        |
| ------------ | ------------------------------------- |
| macOS        | 27.0.1, build 26A434                  |
| Xcode        | 27.0, build 27A266a                   |
| Swift        | Apple Swift 6.4, swiftlang-6.4.0.34.1 |
| Architecture | arm64                                 |

The client runs in an unlocked desktop session with Accessibility permission. It
launches the target executable directly and does not activate the target. The
client is a separate process. Earlier macOS versions have not been tested; the
regression range is unknown.

## Steps to reproduce

1. Extract the attached sample and open Terminal in its directory.
2. Run `make build`. This uses the selected Xcode's Swift compiler and creates
   an app bundle and an accessibility client; it downloads no dependencies.
3. Enable Accessibility permission for Terminal in System Settings, if needed,
   and keep the desktop unlocked.
4. Run `make reproduce`. This runs three variants in separate app processes: a
   label setter, an identifier setter, and a control with neither setter.
5. Compare the `AXPress` return code with `sheetOpened=true` in each line. In
   each variant the client presses “Open sheet” ten times, pressing “Cancel” and
   waiting for dismissal between attempts.

The individual commands, after `make build`, are:

```sh
.build/press .build/AXPressRepro.app/Contents/MacOS/AXPressRepro label
.build/press .build/AXPressRepro.app/Contents/MacOS/AXPressRepro identifier
.build/press .build/AXPressRepro.app/Contents/MacOS/AXPressRepro none
```

The relevant code in `App.swift` is:

```swift
let text = NSTextView(frame: NSRect(x: 0, y: 0, width: 240, height: 80))
text.isEditable = false
text.string = "Sample"
text.setAccessibilityLabel("Specimen")
```

The identifier variant replaces the last line with
`text.setAccessibilityIdentifier("Specimen")`. The control omits that line. All
other app code is shared.

## Expected result

Every successful press of the enabled “Open sheet” button returns
`kAXErrorSuccess` (`0`), and the sheet opens.
[AXUIElementPerformAction documentation](https://developer.apple.com/documentation/applicationservices/1462091-axuielementperformaction).

Apple documents accessibility setters as a supported way to customize AppKit
views and controls. The sample calls those documented methods on a standard
`NSTextView`, which inherits from `NSView`.
[NSAccessibilityProtocol documentation](https://developer.apple.com/documentation/appkit/nsaccessibilityprotocol).

## Actual result

The setter variants can return `kAXErrorFailure` even though the sheet opens.
Omitting the setter removes the failure in the investigated reproducer.
First-press behavior depends on state and timing; a successful first press does
not rule the issue out. Repeat the close and reopen cycle.

The reduced attachment compiles with Swift 6 and warnings treated as errors. Its
fresh live measurement is pending because the desktop was locked when
verification began. The existing, larger standalone investigation reproduced the
setter trigger on 48 of 48 presses. A separate A/B in Typeface/Off on this Mac
completed 45 valid presses in 15 launches per build: 30 of 45 returned `-25200`
in the original app, and zero of 45 failed with the getter workaround. All 90
presses opened the sheet. These are separate experiments.

## Analysis

LLDB traces from the full application show `__NSAccessibilitySetError` recording
an “attribute unimplemented” error for `AXDescription` or `AXIdentifier` from an
`NSTextView` metadata setter, under `NSAccessibilitySetObjectValueForAttribute`,
while AppKit is handling the button's `PerformAction` request. In a failing
request, the next `NSAccessibilityGetAndClearError` is the one at the end of
`PerformAction`. The client then receives `-25200`.

This suggests that an error recorded by a metadata setter during construction of
the sheet leaks into the result of the successful button press. SwiftUI builds
the sheet's view graph within that request. This is the suspected mechanism; the
externally observable failure and setter controls are the evidence for the
report. The attachment uses public APIs to reproduce it.

## Workaround and impact

In Typeface/Off, storing the metadata in an `NSTextView` subclass and serving it
through `accessibilityLabel()` and `accessibilityIdentifier()` overrides
eliminates the measured failure while preserving the accessibility names. The
app's tests pass, and its main-window and sheet accessibility trees match those
of the original app.

An automation client that treats a nonzero AX return code as a failed action
aborts after this successful press. Blindly retrying the action is also unsafe
because the action already ran. The report concerns the incorrect action result;
the client should receive success when the enabled button's action completed and
its sheet opened.

## Attachments

- `App.swift`, `Press.swift`, `Info.plist`, and `Makefile`: the standalone
  sample.
- `README.md`: build and run instructions.
- This report and `full-app-results.txt`: all 90 presses from the separate
  Typeface/Off A/B. These are supporting observations, not measurements of the
  reduced attachment.

[Apple's bug-reporting guidance](https://developer.apple.com/feedback-assistant/).
