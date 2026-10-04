// swift-tools-version:6.2
import PackageDescription

let package = Package(
  name: "SwiftNARADigitalObjectsDemo",
  platforms: [.macOS(.v26)],
  dependencies: [
    .package(url: "https://github.com/KalebCooper/swifty-networking.git", from: "1.3.1"),
    .package(name: "swift-nara", path: "../.."),
  ],
  targets: [
    .executableTarget(
      name: "SwiftNARADigitalObjectsDemo",
      dependencies: [
        .product(name: "HTTPTesting", package: "swifty-networking"),
        .product(name: "SwiftNARADigitalObjects", package: "swift-nara"),
        .product(name: "SwiftNARADigitalObjectsModels", package: "swift-nara"),
      ],
      swiftSettings: [
        .defaultIsolation(nil), .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
        .strictMemorySafety(),
      ])
  ], swiftLanguageModes: [.v6]
)
