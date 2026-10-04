// swift-tools-version:6.2
import PackageDescription

let package = Package(
  name: "swift-nara",
  platforms: [.iOS(.v26), .macOS(.v26), .tvOS(.v26), .visionOS(.v26), .watchOS(.v26)],
  products: [
    .library(name: "SwiftNARACatalogBulk", targets: ["SwiftNARACatalogBulk"]),
    .library(name: "SwiftNARACatalogBulkModels", targets: ["SwiftNARACatalogBulkModels"]),
    .library(name: "SwiftNARADigitalObjects", targets: ["SwiftNARADigitalObjects"]),
    .library(name: "SwiftNARADigitalObjectsModels", targets: ["SwiftNARADigitalObjectsModels"]),
  ],
  traits: [
    .default(enabledTraits: []),
    .trait(name: "HTTPPortable", description: "Enable the portable Linux and Android transport."),
  ],
  dependencies: [
    .package(url: "https://github.com/apple/swift-crypto.git", from: "5.0.0"),
    // HTTPCore exposes these header types without re-exporting their module.
    .package(url: "https://github.com/apple/swift-http-types.git", from: "1.6.0"),
    .package(url: "https://github.com/apple/swift-system.git", from: "1.8.0"),
    // 1.3.1 supplies custom page decoding and streamed status/header receipts.
    .package(
      url: "https://github.com/KalebCooper/swifty-networking.git", from: "1.3.1",
      traits: [.trait(name: "HTTPPortable", condition: .when(traits: ["HTTPPortable"]))]),
  ],
  targets: [
    .target(
      name: "SwiftNARACatalogBulk",
      dependencies: [
        .product(name: "Crypto", package: "swift-crypto"),
        .product(name: "HTTPCore", package: "swifty-networking"),
        .product(
          name: "HTTPPortable", package: "swifty-networking",
          condition: .when(traits: ["HTTPPortable"])),
        .product(name: "HTTPTypes", package: "swift-http-types"),
        .product(
          name: "HTTPURLSession", package: "swifty-networking",
          condition: .when(platforms: [.iOS, .macCatalyst, .macOS, .tvOS, .visionOS, .watchOS])),
        "SwiftNARACatalogBulkModels",
        .product(name: "SystemPackage", package: "swift-system"),
      ], swiftSettings: swiftSettings),
    .target(name: "SwiftNARACatalogBulkModels", swiftSettings: swiftSettings),
    .target(
      name: "SwiftNARACatalogBulkTestSupport", resources: [.copy("Fixtures")],
      swiftSettings: swiftSettings),
    .target(
      name: "SwiftNARADigitalObjects",
      dependencies: [
        .product(name: "Crypto", package: "swift-crypto"),
        .product(name: "HTTPCore", package: "swifty-networking"),
        .product(
          name: "HTTPPortable", package: "swifty-networking",
          condition: .when(traits: ["HTTPPortable"])),
        .product(name: "HTTPTypes", package: "swift-http-types"),
        .product(
          name: "HTTPURLSession", package: "swifty-networking",
          condition: .when(platforms: [.iOS, .macCatalyst, .macOS, .tvOS, .visionOS, .watchOS])),
        "SwiftNARADigitalObjectsModels",
        .product(name: "SystemPackage", package: "swift-system"),
      ], swiftSettings: swiftSettings),
    .target(name: "SwiftNARADigitalObjectsModels", swiftSettings: swiftSettings),
    .target(
      name: "SwiftNARADigitalObjectsTestSupport", resources: [.copy("Fixtures")],
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
    .testTarget(
      name: "SwiftNARADigitalObjectsModelsTests",
      dependencies: ["SwiftNARADigitalObjectsModels", "SwiftNARADigitalObjectsTestSupport"],
      swiftSettings: swiftSettings),
    .testTarget(
      name: "SwiftNARADigitalObjectsTests",
      dependencies: [
        .product(name: "HTTPTesting", package: "swifty-networking"),
        .product(name: "HTTPTypes", package: "swift-http-types"),
        "SwiftNARADigitalObjects", "SwiftNARADigitalObjectsModels",
        "SwiftNARADigitalObjectsTestSupport",
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
