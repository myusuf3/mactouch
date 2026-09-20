// swift-tools-version:5.9
import PackageDescription

let package = Package(
  name: "MacTouch",
  platforms: [.macOS(.v13)],
  products: [
    .library(name: "MacTouchKit", targets: ["MacTouchKit"]),
    .executable(name: "mactouch", targets: ["MacTouchCLI"]),
    .executable(name: "mactouchd", targets: ["MacTouchDaemon"]),
    .executable(name: "MacTouch", targets: ["MacTouchApp"]),
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
    .executableTarget(name: "MacTouchApp", dependencies: ["MacTouchKit"]),
    .testTarget(name: "MacTouchKitTests", dependencies: ["MacTouchKit"]),
  ]
)
