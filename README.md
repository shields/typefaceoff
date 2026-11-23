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

# Typeface/Off

Typeface/Off compares fonts installed on your Mac. Read the same passage in two
typefaces, overlay individual glyphs to see where their shapes and spacing
differ, and check which languages each font covers. The app runs offline on
macOS 15 or later.

## Install

Published disk images appear on
[GitHub Releases](https://github.com/shields/typefaceoff/releases). Open the DMG
and drag TypefaceOff to Applications. The first published cask will also be
available through `brew install --cask shields/tap/typefaceoff`.

## Run from source

Building requires Xcode 27 with Swift 6.4 or later. From the repository root,
install the build tools and launch the app.

```sh
brew install xcodegen jq
make run
```

## Documentation

- [Comparing fonts](docs/usage.md)
- [Development and benchmarks](docs/development.md)
- [UI fuzzing](docs/fuzzing.md)
- [DMG, Homebrew, and Mac App Store releases](docs/releases.md)
- [TestFlight distribution](docs/testflight.md)
