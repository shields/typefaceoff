// swift-tools-version: 6.4
// Copyright © 2026 Michael Shields
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import PackageDescription

let package = Package(
  name: "TypefaceOff",
  platforms: [.macOS(.v15)],
  products: [
    .library(name: "TypefaceCore", targets: ["TypefaceCore"]),
    .executable(name: "ui-fuzz", targets: ["UIFuzz"]),
  ],
  dependencies: [
    .package(url: "https://github.com/apple/swift-argument-parser", exact: "1.8.2")
  ],
  targets: [
    .target(
      name: "TypefaceCore",
      resources: [
        .copy("Resources/character-frequencies.tsv"), .copy("Resources/languages.json"),
        .copy("Resources/Hyperglot-LICENSE"),
      ],
      swiftSettings: [.treatAllWarnings(as: .error)]),
    .target(name: "UIFuzzSupport", swiftSettings: [.treatAllWarnings(as: .error)]),
    .executableTarget(
      name: "UIFuzz",
      dependencies: [
        "UIFuzzSupport",
        .product(name: "ArgumentParser", package: "swift-argument-parser"),
      ],
      swiftSettings: [.treatAllWarnings(as: .error)]),
    .testTarget(
      name: "TypefaceCoreTests", dependencies: ["TypefaceCore"],
      swiftSettings: [.treatAllWarnings(as: .error)]),
    .testTarget(
      name: "UIFuzzTests", dependencies: ["UIFuzzSupport"],
      swiftSettings: [.treatAllWarnings(as: .error)]),
  ],
  swiftLanguageModes: [.v6]
)
