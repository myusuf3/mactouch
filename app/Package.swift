// swift-tools-version:5.9
import PackageDescription

let package = Package(
  name: "MacTouch",
  platforms: [.macOS(.v13)],
  products: [
    .library(name: "MacTouchKit", targets: ["MacTouchKit"]),
    .executable(name: "mactouch", targets: ["MacTouchCLI"]),
    .executable(name: "mactouchd", targets: ["MacTouchDaemon"]),
    .executable(name: "MacTouchApp", targets: ["MacTouchApp"]),
  ],
  targets: [
    .target(
      name: "MacTouchKit",
      linkerSettings: [
        .linkedFramework("IOKit"),
        .linkedFramework("CoreAudio"),
        .linkedFramework("CoreMediaIO"),
      ]
    ),
    .executableTarget(name: "MacTouchCLI", dependencies: ["MacTouchKit"]),
    .executableTarget(name: "MacTouchDaemon", dependencies: ["MacTouchKit"]),
    .target(name: "MacTouchModel", dependencies: ["MacTouchKit"]),
    .executableTarget(name: "MacTouchApp", dependencies: ["MacTouchKit", "MacTouchModel"]),
    .testTarget(name: "MacTouchKitTests", dependencies: ["MacTouchKit"]),
    .testTarget(name: "MacTouchModelTests", dependencies: ["MacTouchModel"]),
  ]
)
