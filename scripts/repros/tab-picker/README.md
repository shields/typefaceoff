# NSTabPickerViewController observer-removal crash

This standalone SwiftUI app reproduces an AppKit crash in macOS 27.0. It opens
the system tab overview, creates a tab, changes a slider, and closes the tab
overview. `NSTabPickerViewController.dealloc` then removes an
`effectiveAppearance` observer from the SwiftUI window even though that observer
is not registered.

Build the app and its Accessibility client with the selected Xcode:

```sh
make build
```

Give the process running the client Accessibility and event-posting permission,
keep the desktop unlocked, and run:

```sh
make reproduce
```

The command exits successfully only when the app terminates through `SIGABRT`.
Pass `--native-appearance` after the executable when invoking `.build/reproduce`
directly to omit the app's forced dark appearance; both variants reproduce on
macOS 27.0 (26A428).
