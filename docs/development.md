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

# Development

## Setup

From the repository root, install the development tools and Git hooks. Building
requires Xcode 27 with Swift 6.4 or later.

```sh
brew install xcodegen bun node lefthook zizmor shellcheck shfmt jq uv gh
make setup
make actions-lock-install
```

Use `make run` to build and launch the app, `make test` to run the tests,
`make coverage` to check coverage, `make lint` to check formatting and lint
rules, and `make fmt` to format the source and documentation.

`make build` creates `.build/xcode/Build/Products/Debug/TypefaceOff.app`, signed
locally with an ad hoc identity by default. `make project` generates
`TypefaceOff.xcodeproj` for development in Xcode. `project.yml` owns the project
and app metadata; generated files are ignored. Signing entitlements are in
`Config/*.entitlements`.

## Development signing

To preserve macOS privacy permissions across development builds, create
`Config/Development.local.xcconfig` with your Apple Development identity:

```xcconfig
DEVELOPMENT_TEAM = YOUR_TEAM_ID
CODE_SIGN_IDENTITY = Apple Development
```

This ignored file applies to normal, fuzz, and benchmark development builds.
`Config/Signing.local.xcconfig` also supplies shared signing settings when
present. Ad hoc signatures identify each build separately, which can cause
repeated file-access prompts when running from a removable volume. A stable
signing identity lets macOS recognize successive builds as the same app; you may
need to grant permission once after switching identities. See Apple’s
[code identity documentation](https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements).

## Tests and coverage

`Sources/TypefaceCore` is a Swift package for font discovery, shaping,
measurements, calibrated edits, matching, and ranking. `Sources/TypefaceOff`
contains the macOS UI and in-memory comparison state. Tests use Swift Testing:
SwiftPM runs the core tests, and Xcode runs the native tests inside the app. The
test host runs with activation prohibited so it cannot steal desktop focus.
`make test-app` runs only the native suite, saves its result bundle in
`.build/TestResults.xcresult`, and prints assertion failures when tests fail. A
runtime warning, such as SwiftUI’s, fails the run. `make coverage` runs both
with instrumentation and reports coverage through `llvm-cov`, requiring 100%
line and region coverage for every engine, app, and reusable fuzzing-support
source file. Tests for Inter’s optional variable axes and character variants
require that font to be installed.

The app supports macOS 15, but Xcode 27 needs macOS 26.6, and Xcode 26.4 and
later need macOS 26.2, so macOS 15 runs at most Xcode 26.3. CI builds the test
bundles with Xcode 27 and runs them without rebuilding on macOS 15 and 26, using
the Xcode 26 those runners have; the main job builds and tests separately on
macOS 27. `make build-for-testing` packs the core and native test bundles into
`.build/portable-tests.tar`, and the Swift Testing runtime and overlays of the
Xcode that built them into `.build/portable-runtime.tar`. `make stage-support`,
run with Xcode 26.6, packs its XCTest support library and XCTestCore into
`.build/support.tar`. `make test-without-building RUNTIME=…` unpacks the bundles
and runs them with the active Xcode, saving results like `make test-app`;
`testing` also unpacks the Testing runtime, and `support` that and the staged
XCTest support. `make smoke-launch` starts the built app and fails if it exits
within 15 seconds, so an older macOS checks the binary itself. A run that
executes no tests fails. A push to `main` skips the macOS jobs when
`make ci-reuse` finds a branch run of the same tree, finished within the last
day, whose every job passed on GitHub-hosted runners.

The project uses Swift 6 language mode, strict concurrency, and warnings as
errors. See the
[shared development conventions](https://github.com/shields/right-answers) and
the [UI fuzzing guide](fuzzing.md).

## Visual review and benchmarks

`make review` renders native text, glyph, single-font, and character search
windows, Match and the comparison inspector into `.build/review` (override with
`REVIEW_DIR`) for visual inspection and records glyph redraw timings in
`glyph-performance.json`. It requires an active macOS desktop session.

`make benchmark-startup` launches the optimized, sandboxed app in fresh
processes with coverage disabled. It measures process launch through the first
drawn pair of specimens and through the displayed initial ranking and typography
previews. One warmup is reported separately, followed by seven measured
launches; set `STARTUP_RUNS=…` to change the count and `STARTUP_OUTPUT=…` to
retain a baseline. `.build/startup-benchmark.json` records every run, phase
timestamps, medians, 90th percentiles, OS, revision, and executable hash. It
requires an active desktop session and opens and closes its own app windows. OS
and font caches are not flushed, so this measures repeated launches, not the
first launch after a reboot. Startup probes are compiled only into the dedicated
benchmark configuration.

`make profile-startup` samples one launch of the same optimized app at one
millisecond intervals using macOS’s `sample` profiler. It attaches just after
process creation, records two seconds, and closes its own app. The call stacks
are saved to `.build/startup-profile.txt`, with phase timestamps in
`.build/startup-profile.txt.launch.log`; set `STARTUP_PROFILE=…` to retain a
profile. Use `make benchmark-startup` for timings without profiler overhead.

`make benchmark-highlights` measures the latency of toggling Shape, Spacing, and
Frequency on a long specimen. The [highlight benchmark](highlight-benchmark.md)
includes instructions for comparing revisions and the recorded results.

## Font similarity

Family ranking and fitting use an **experimental visual heuristic**, without a
calibrated confidence percentage or a human-validated ranking claim. Four
equally weighted components compare glyph distance fields, glyph ink at three
blur scales, shaped text, and advance/bearing/vertical metrics. Rasterization
preserves point size, display scale, baseline, and origin; blank padding
contributes no similarity. A shared 128 MiB LRU cache reuses renderings,
including inert feature settings, while retaining variation axes in the cache
key. Family ranking defaults to one concurrent comparison per available CPU core
and publishes results as they finish; cache access remains synchronized.
`make benchmark` also records ranking times with one worker, four workers, and
the available core count in `ranking-timings.json`, checking that all produce
identical scores.

The versioned ranking corpus covers printable ASCII, selected Latin accents, and
feature/spacing diagnostics. Fitting adds all distinct current characters and up
to 128 deterministically sampled words. It validates coverage of the complete
current text before searching and never compares a fallback font. The search
uses categorical combinations or a bounded beam, multiple continuous starting
points, joint axis steps, and progressively smaller steps. It is budget-limited
and cannot guarantee a global optimum. See the
[research and evaluation rationale](research/font-similarity.md).

`make benchmark` runs an opt-in release benchmark and writes
`.build/similarity-benchmark/scores.json`, rendered specimens, and
`review.html`. It compares the existing glyph IoU, signed distance fields,
multiscale ink, SSIM, MS-SSIM, and the combined score at 14, 22, and 36 points.
Open the HTML locally for blind triplet judgments with ties; download judgments
and import multiple reviewers’ files to calculate individual and majority
agreement. Nothing is uploaded. The JSON records configurations, component
scores, corpus and score versions, OS, scale, runtime, and quick/refined fit
results. `character-search.json` records character search index and query
timings.
