// swift-tools-version:6.2
import PackageDescription

let package = Package(
  name: "swift-nara",
  platforms: [.iOS(.v26), .macOS(.v26), .tvOS(.v26), .visionOS(.v26), .watchOS(.v26)],
  products: [
    .library(name: "SwiftNARACatalogBulk", targets: ["SwiftNARACatalogBulk"]),
    .library(name: "SwiftNARACatalogBulkModels", targets: ["SwiftNARACatalogBulkModels"]),
  ],
  traits: [
    .default(enabledTraits: []),
    .trait(name: "HTTPPortable", description: "Enable the portable Linux and Android transport."),
  ],
  dependencies: [
    // HTTPCore exposes these header types without re-exporting their module.
    .package(url: "https://github.com/apple/swift-http-types.git", from: "1.6.0"),
    // 1.3.1 supplies custom page decoding and streamed status/header receipts.
    .package(
      url: "https://github.com/KalebCooper/swifty-networking.git", from: "1.3.1",
      traits: [.trait(name: "HTTPPortable", condition: .when(traits: ["HTTPPortable"]))]),
  ],
  targets: [
    .target(
      name: "SwiftNARACatalogBulk",
      dependencies: [
        .product(name: "HTTPCore", package: "swifty-networking"),
        .product(
          name: "HTTPPortable", package: "swifty-networking",
          condition: .when(traits: ["HTTPPortable"])),
        .product(name: "HTTPTypes", package: "swift-http-types"),
        .product(
          name: "HTTPURLSession", package: "swifty-networking",
          condition: .when(platforms: [.iOS, .macCatalyst, .macOS, .tvOS, .visionOS, .watchOS])),
        "SwiftNARACatalogBulkModels",
      ], swiftSettings: swiftSettings),
    .target(name: "SwiftNARACatalogBulkModels", swiftSettings: swiftSettings),
    .target(
      name: "SwiftNARACatalogBulkTestSupport", resources: [.copy("Fixtures")],
      swiftSettings: swiftSettings),
    .testTarget(
      name: "SwiftNARACatalogBulkModelsTests",
      dependencies: ["SwiftNARACatalogBulkModels", "SwiftNARACatalogBulkTestSupport"],
      swiftSettings: swiftSettings),
    .testTarget(
      name: "SwiftNARACatalogBulkTests",
      dependencies: [
        .product(name: "HTTPCore", package: "swifty-networking"),
        .product(name: "HTTPTesting", package: "swifty-networking"),
        .product(name: "HTTPTypes", package: "swift-http-types"),
        "SwiftNARACatalogBulk", "SwiftNARACatalogBulkModels", "SwiftNARACatalogBulkTestSupport",
      ], swiftSettings: swiftSettings),
  ],
  swiftLanguageModes: [.v6]
)

// Preserve caller isolation and explicit memory-safety checking on every target.
var swiftSettings: [SwiftSetting] {
  [
    .defaultIsolation(nil), .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
    .strictMemorySafety(),
  ]
}
