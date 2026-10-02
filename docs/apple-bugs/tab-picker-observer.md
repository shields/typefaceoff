# NSTabPickerViewController removes an unregistered effectiveAppearance observer

Status: ready for Feedback Assistant submission; not submitted.

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

## Environment and regression range

The same app and client binaries were built once with Xcode 27 and a macOS 15
deployment target, then run in arm64 virtual machines:

| macOS  | Build  | Forced dark appearance | Native appearance     |
| ------ | ------ | ---------------------- | --------------------- |
| 15.7.7 | 24G720 | No crash, 2 of 2 runs  | No crash, 2 of 2 runs |
| 26.6.2 | 25G83  | No crash, 2 of 2 runs  | No crash, 2 of 2 runs |
| 27.0   | 26A428 | Crash, 2 of 2 runs     | Crash, 2 of 2 runs    |

| Component    | Version                |
| ------------ | ---------------------- |
| Xcode        | 27.0, build 27A266a    |
| Swift        | Apple Swift 6.4.0.34.1 |
| Architecture | arm64                  |

Every run completed all five UI actions. The control runs printed
`The app did not crash`; every macOS 27 run terminated with the expected
`SIGABRT`. This places the regression after macOS 26.6.2 and at or before macOS
27.0. The original application crash and the standalone app have the same
exception reason and top AppKit frames.

## Steps to reproduce

1. Extract the attached `tab-picker` directory and open Terminal there.
2. Run `make build` with Xcode 27 selected. This downloads no dependencies.
3. Give Terminal Accessibility and Input Monitoring permission, if needed, and
   leave the desktop unlocked.
4. Run `make reproduce`.

The client performs these actions:

1. Press the View menu.
2. Activate the menu item identified as `toggleTabOverview:`.
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

Running the exact same binaries on macOS 15.7.7 and 26.6.2 completed the
sequence without an exception, ruling out the Xcode 27 compiler and SDK as the
sole trigger.

Any SwiftUI app that receives the standard tabbing menu can expose the sequence
to a user without implementing tab support itself. The exception is raised by
AppKit teardown and cannot be caught from Swift.

## Attachments

- `App.swift`: standalone SwiftUI app.
- `Reproduce.swift`: Accessibility client and result check.
- `Info.plist` and `Makefile`: dependency-free build.
