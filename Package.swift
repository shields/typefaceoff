// swift-tools-version: 6.3
import PackageDescription

let package = Package(
  name: "TypefaceOff",
  platforms: [.macOS(.v15)],
  products: [
    .library(name: "TypefaceCore", targets: ["TypefaceCore"]),
    .executable(name: "TypefaceOff", targets: ["TypefaceOff"]),
  ],
  targets: [
    .target(name: "TypefaceCore", swiftSettings: [.treatAllWarnings(as: .error)]),
    .executableTarget(
      name: "TypefaceOff", dependencies: ["TypefaceCore"],
      swiftSettings: [.treatAllWarnings(as: .error)]),
    .testTarget(
      name: "TypefaceCoreTests", dependencies: ["TypefaceCore"],
      swiftSettings: [.treatAllWarnings(as: .error)]),
    .testTarget(
      name: "TypefaceOffTests", dependencies: ["TypefaceOff"],
      swiftSettings: [.treatAllWarnings(as: .error)]),
  ],
  swiftLanguageModes: [.v6]
)
