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

The Makefile targets the running Mac's architecture with a macOS 15 deployment
target so the same binaries can establish the OS regression range.

Give the process running the client Accessibility and event-posting permission,
keep the desktop unlocked, and run:

```sh
make reproduce
```

The command exits successfully only when the app terminates through `SIGABRT`;
an unaffected system exits with `The app did not crash`. Pass
`--native-appearance` after the executable when invoking `.build/reproduce`
directly to omit the app's forced dark appearance.

The same binaries completed the sequence without crashing on macOS 15.7.7
(24G720) and 26.6.2 (25G83), then reproduced twice in each appearance mode on
macOS 27.0 (26A428).
