/// Caller identity and explicit resource bounds for the bulk client.
public struct CatalogBulkConfiguration: Sendable {
  /// The maximum bytes buffered for a manifest or custom single response.
  public let maximumManifestBytes: Int
  /// The maximum bytes accepted for one streamed shard download.
  public let maximumShardBytes: Int64
  /// The caller's application identity and contact information.
  public let userAgent: String

  /// Creates a resource-bounded configuration.
  /// - Parameters:
  ///   - maximumManifestBytes: The buffered response bound, defaulting to 4 MiB.
  ///   - maximumShardBytes: The download bound, defaulting to 1 GiB.
  ///   - userAgent: An explicit application identity; no identity is invented.
  /// - Throws: `CatalogBulkError.invalidConfiguration` for invalid bounds or identity.
  public init(
    maximumManifestBytes: Int = 4 * 1024 * 1024, maximumShardBytes: Int64 = 1024 * 1024 * 1024,
    userAgent: String
  ) throws(CatalogBulkError) {
    guard maximumManifestBytes > 0, maximumShardBytes > 0, !userAgent.isEmpty,
      !userAgent.unicodeScalars.contains(where: { $0.value < 32 || $0.value == 127 })
    else { throw .invalidConfiguration }
    self.maximumManifestBytes = maximumManifestBytes
    self.maximumShardBytes = maximumShardBytes
    self.userAgent = userAgent
  }
}
