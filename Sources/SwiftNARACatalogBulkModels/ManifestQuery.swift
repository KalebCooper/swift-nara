#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// Invalid source inputs or inconsistent S3 continuation metadata.
public enum ManifestError: Error, Hashable, Sendable {
  /// The bucket, prefix, limit, or echoed token differs from the request.
  case inconsistentPage
  /// An input limit, prefix, or token is invalid.
  case invalidQuery
  /// A truncated listing omitted its next token or returned no objects.
  case missingContinuation
  /// The next token has already been used by this traversal.
  case repeatedContinuation
}

/// An immutable S3 ListObjectsV2 query for the public NARA bulk bucket.
///
/// Tokens are opaque. No offset, stable snapshot, or historical completeness is implied.
/// ```swift
/// let query = try ManifestQuery(prefix: "descriptions/record-groups/rg_11/")
/// ```
public struct ManifestQuery: Hashable, Sendable {
  /// The opaque token for this page, if any.
  public let continuationToken: String?
  /// The maximum number of keys, from 1 through 1,000.
  public let maxKeys: Int
  /// The exact key prefix; empty lists the bucket.
  public let prefix: String

  /// Creates a listing query without sending a request.
  /// - Parameters:
  ///   - continuationToken: A nonempty S3 token, used unchanged.
  ///   - maxKeys: A page bound; defaults to 1,000.
  ///   - prefix: A source key prefix, not a URL.
  /// - Throws: `ManifestError.invalidQuery` for invalid bounds or control characters.
  public init(continuationToken: String? = nil, maxKeys: Int = 1000, prefix: String = "")
    throws(ManifestError)
  {
    guard (1...1000).contains(maxKeys),
      !prefix.unicodeScalars.contains(where: { $0.value < 32 || $0.value == 127 }),
      continuationToken.map({
        !$0.isEmpty && !$0.unicodeScalars.contains(where: { $0.value < 32 || $0.value == 127 })
      }) ?? true
    else { throw .invalidQuery }
    self.continuationToken = continuationToken
    self.maxKeys = maxKeys
    self.prefix = prefix
  }

  /// Validates a page and describes its continuation.
  /// - Parameter page: The page returned for this exact query.
  /// - Returns: The next query, or nil only for a valid terminal page.
  /// - Throws: A `ManifestError` for inconsistent or nonprogressing metadata.
  public func next(after page: BulkManifest) throws(ManifestError) -> Self? {
    guard page.name == "nara-national-archives-catalog", page.prefix == prefix,
      page.maxKeys == maxKeys, page.continuationToken == continuationToken,
      page.keyCount == page.objects.count, page.keyCount <= maxKeys,
      page.objects.allSatisfy({ $0.key.hasPrefix(prefix) })
    else { throw .inconsistentPage }
    guard page.isTruncated else {
      guard page.nextContinuationToken == nil else { throw .inconsistentPage }
      return nil
    }
    guard let token = page.nextContinuationToken, !token.isEmpty, !page.objects.isEmpty else {
      throw .missingContinuation
    }
    guard token != continuationToken else { throw .repeatedContinuation }
    return try Self(continuationToken: token, maxKeys: maxKeys, prefix: prefix)
  }
}
