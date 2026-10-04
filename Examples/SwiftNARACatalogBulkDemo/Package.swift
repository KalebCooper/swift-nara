// swift-tools-version:6.2
import PackageDescription

let package = Package(
  name: "SwiftNARACatalogBulkDemo",
  platforms: [.macOS(.v26)],
  dependencies: [
    // Builds recorded 304 headers into HTTPFields for the mock transport's replay.
    .package(url: "https://github.com/apple/swift-http-types.git", from: "1.6.0"),
    .package(name: "swift-nara", path: "../.."),
    .package(url: "https://github.com/KalebCooper/swifty-networking.git", from: "1.3.1"),
  ],
  targets: [
    .executableTarget(
      name: "SwiftNARACatalogBulkDemo",
      dependencies: [
        .product(name: "HTTPTesting", package: "swifty-networking"),
        .product(name: "HTTPTypes", package: "swift-http-types"),
        .product(name: "SwiftNARACatalogBulk", package: "swift-nara"),
        .product(name: "SwiftNARACatalogBulkModels", package: "swift-nara"),
      ],
      swiftSettings: [
        .defaultIsolation(nil), .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
        .strictMemorySafety(),
      ]
    )
  ],
  swiftLanguageModes: [.v6]
)
