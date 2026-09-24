// swift-tools-version: 6.3
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
      name: "TypefaceCore", resources: [.copy("Resources/character-frequencies.tsv")],
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
