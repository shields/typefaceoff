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

# TestFlight distribution

Sign in to your Apple Developer account in Xcode, then create
`Config/Signing.local.xcconfig` with `DEVELOPMENT_TEAM = YOUR_TEAM_ID`. This
file is ignored by Git. Register `com.typefaceoff` and create a macOS app named
“Typeface/Off” in [App Store Connect](https://appstoreconnect.apple.com/apps).

Install the archive tools with `brew install syft jq`.

Commit the release changes on `main`, then run:

```sh
make coverage
make lint
make archive
make testflight
```

`make archive` creates `.build/distribution/TypefaceOff.xcarchive` for Intel and
Apple silicon. `make testflight` creates a fresh archive and uploads it using
Xcode’s signed-in account and automatic signing. Archiving alone does not
upload. The app icon is packaged in `Sources/TypefaceOff/AppIcon.icon`.

Release versions use [gitcalver](https://gitcalver.org): `0.YYYYMMDD.N`, derived
from the release commit, with build number `YYYYMMDD.N`. Unlike iOS, macOS
[requires build numbers to increase across versions](https://developer.apple.com/documentation/xcode/preparing-your-app-for-distribution).
The vendored `tools/gitcalver.sh` is the unmodified
[v20260825.1 release](https://github.com/gitcalver/sh/releases/tag/v20260825.1).
Dirty working trees and commits outside the default branch are rejected. Each
upload needs a new commit; Xcode does not rewrite the version or build number.
Development builds use `0.0.0` with build number `0`.

The Release configuration selects `Config/TestFlight.entitlements`, which
enables the sandbox and an empty Keychain Sharing entitlement. Apple
[recommends the empty entitlement](https://developer.apple.com/forums/thread/733942)
to make Xcode embed the provisioning profile required by TestFlight.

After Apple processes the upload, configure test information and tester groups
on the app’s TestFlight tab. External testing requires TestFlight App Review.

## Bill of materials and notices

Both `make archive` and `make testflight` generate `TypefaceOff.spdx.json` at
the root of the finished `.xcarchive`. Keep the report with its archive. Its
file hashes describe that particular build. CI runs the same checks on an
unsigned universal archive and publishes its report as the **TypefaceOff-sbom**
workflow artifact.

Choose **Typeface/Off → About Typeface/Off → Acknowledgments** to open the
bundled text file in your default text viewer. Each build adds the Hyperglot
version, FineFreq commit, and Wikipedia revision from its data resources to the
reviewed attribution in [NOTICE](../NOTICE).

The archive check verifies the notice against the bundled resources. Syft
inventories the bundle, and the link maps and load commands identify libraries
in each architecture. If the scan finds an unrecognized package or library, the
SBOM identifies it and the archive check stops the upload. When adding
third-party data, artwork, text, or code, update the attribution in `NOTICE` and
the source relationships in `scripts/app-sbom.jq`. For a local check,
`make ci-archive` builds an unsigned archive under `.build/ci-distribution`.
