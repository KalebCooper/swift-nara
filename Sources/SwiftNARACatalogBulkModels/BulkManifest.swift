#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// One complete, unfiltered S3 listing page.
///
/// Use `ManifestCodec` to read XML. Codable is for persisting the decoded value as JSON.
public struct BulkManifest: Codable, Hashable, Sendable, CatalogBulkResponse {
  /// The token echoed by S3, if one was requested.
  public let continuationToken: String?
  /// Whether S3 reports more keys.
  public let isTruncated: Bool
  /// The number of keys reported in this page.
  public let keyCount: Int
  /// The requested page bound echoed by S3.
  public let maxKeys: Int
  /// The bucket name.
  public let name: String
  /// The next opaque token, if present.
  public let nextContinuationToken: String?
  /// Every object, in provider order, including non-JSONL objects.
  public let objects: [BulkObject]
  /// The prefix echoed by S3.
  public let prefix: String

  /// Creates a decoded page without interpreting its continuation.
  public init(
    continuationToken: String? = nil, isTruncated: Bool, keyCount: Int, maxKeys: Int,
    name: String, nextContinuationToken: String? = nil, objects: [BulkObject], prefix: String
  ) {
    self.continuationToken = continuationToken
    self.isTruncated = isTruncated
    self.keyCount = keyCount
    self.maxKeys = maxKeys
    self.name = name
    self.nextContinuationToken = nextContinuationToken
    self.objects = objects
    self.prefix = prefix
  }

  /// Decodes a bounded UTF-8 S3 XML response.
  /// - Parameter data: The original response bytes.
  /// - Returns: The listing with its exact token and object order.
  /// - Throws: `CatalogDecodingError` for invalid or oversized XML.
  public static func decode(_ data: Data) throws(CatalogDecodingError) -> Self {
    try ManifestCodec.decode(data)
  }
}
