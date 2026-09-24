#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// A validated JSONL key from the public bulk distribution.
public struct ShardReference: Hashable, Sendable {
  /// The original S3 key.
  public let key: String
  /// An optional S3 version identifier, distinct from an ETag.
  public let versionID: String?

  /// Creates a shard reference without downloading it.
  /// - Parameters:
  ///   - key: A `.jsonl` key under descriptions or authority-records.
  ///   - versionID: A nonempty opaque S3 version, if known.
  /// - Throws: `ManifestError.invalidQuery` for an invalid key or version.
  public init(key: String, versionID: String? = nil) throws(ManifestError) {
    guard key.hasSuffix(".jsonl"),
      key.hasPrefix("descriptions/") || key.hasPrefix("authority-records/"),
      !key.contains("\\"),
      !key.unicodeScalars.contains(where: { $0.value < 32 || $0.value == 127 }),
      !key.split(separator: "/", omittingEmptySubsequences: false).contains(where: {
        $0 == "." || $0 == ".." || $0.isEmpty
      }),
      versionID.map({
        !$0.isEmpty && !$0.unicodeScalars.contains(where: { $0.value < 32 || $0.value == 127 })
      }) ?? true
    else { throw .invalidQuery }
    self.key = key; self.versionID = versionID
  }
}
