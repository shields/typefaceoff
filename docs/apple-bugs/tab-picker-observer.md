# NSTabPickerViewController removes an unregistered effectiveAppearance observer

Status: prepared for Feedback Assistant; not submitted.

Suggested Feedback Assistant topic: Developer Technologies & SDKs, macOS,
AppKit. SwiftUI supplies the window and scene.

## Summary

A standard SwiftUI `WindowGroup` crashes after using macOS's built-in tab
overview. `NSTabPickerViewController.dealloc` asks the SwiftUI window to remove
an `effectiveAppearance` observer that is not registered. Foundation raises an
`NSRangeException`, and the app terminates with `SIGABRT`.

The attached app contains one `Text`, one `Slider`, and no AppKit integration.
The attached Accessibility client performs the reduced five-action sequence and
requires the expected signal, making the attachment self-checking.

## Environment

| Component    | Tested version         |
| ------------ | ---------------------- |
| macOS        | 27.0, build 26A428     |
| Xcode        | 27.0, build 27A266a    |
| Swift        | Apple Swift 6.4.0.34.1 |
| Architecture | arm64 virtual machine  |

The result was reproduced twice with `.preferredColorScheme(.dark)` and twice
with native appearance. The original application crash and the standalone app
have the same exception reason and top AppKit frames.

## Steps to reproduce

1. Extract the attached `tab-picker` directory and open Terminal there.
2. Run `make build` with Xcode 27 selected. This downloads no dependencies.
3. Give Terminal Accessibility and Input Monitoring permission, if needed, and
   leave the desktop unlocked.
4. Run `make reproduce`.

The client performs these actions:

1. Press the View menu.
2. Click the menu item identified as `toggleTabOverview:`.
3. Click New Tab.
4. Drag the app's slider.
5. Press Escape.

To run the native-appearance control directly:

```sh
.build/reproduce .build/TabPickerRepro.app/Contents/MacOS/TabPickerRepro --native-appearance
```

## Expected result

The tab overview closes and the app remains open.

## Actual result

The app terminates with this exception:

```text
NSRangeException: Cannot remove an observer <NSTabPickerViewController ...> for
the key path "effectiveAppearance" from <SwiftUI.AppKitWindow ...> because it is
not registered as an observer.
```

The top relevant stack frames are
`-[NSObject(NSKeyValueObserverRegistration) removeObserver:forKeyPath:context:]`,
`-[NSWindow removeObserver:forKeyPath:context:]`, and
`-[NSTabPickerViewController dealloc]`.

## Reduction and impact

Coverage-guided UI fuzzing first found the crash in Typeface/Off in a 26-action
trace. Automated reduction produced the five actions above. Replacing the full
application with the attached two-control SwiftUI view preserved the crash.
Removing the forced color scheme also preserved it, ruling out application state
and explicit appearance as necessary triggers.

Any SwiftUI app that receives the standard tabbing menu can expose the sequence
to a user without implementing tab support itself. The exception is raised by
AppKit teardown and cannot be caught from Swift.

## Attachments

- `App.swift`: standalone SwiftUI app.
- `Reproduce.swift`: Accessibility client and result check.
- `Info.plist` and `Makefile`: dependency-free build.
