#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// One S3 object entry, preserving provider version hints and timestamps.
///
/// ETags are opaque and must not be interpreted as SHA-256 digests.
public struct BulkObject: Codable, Hashable, Sendable {
  /// The provider's ETag including its original quotation marks.
  public let eTag: String
  /// The exact decoded S3 key.
  public let key: String
  /// The original S3 modification timestamp.
  public let lastModified: String
  /// The advertised byte count.
  public let size: Int64
  /// The open S3 storage-class value.
  public let storageClass: String?

  /// Creates an object entry from source metadata.
  public init(
    eTag: String, key: String, lastModified: String, size: Int64, storageClass: String? = nil
  ) {
    self.eTag = eTag
    self.key = key
    self.lastModified = lastModified
    self.size = size
    self.storageClass = storageClass
  }
}
