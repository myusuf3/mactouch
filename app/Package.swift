// swift-tools-version:5.9
import PackageDescription

let package = Package(
  name: "MacTouch",
  platforms: [.macOS(.v13)],
  products: [
    .library(name: "MacTouchKit", targets: ["MacTouchKit"]),
    .executable(name: "mactouch", targets: ["MacTouchCLI"]),
  ],
  targets: [
    .target(
      name: "MacTouchKit",
      linkerSettings: [.linkedFramework("IOKit")]
    ),
    .executableTarget(name: "MacTouchCLI", dependencies: ["MacTouchKit"]),
    .testTarget(name: "MacTouchKitTests", dependencies: ["MacTouchKit"]),
  ]
)
