#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// A known bulk representation selected by key, strong ETag, length and optional version.
///
/// Supports JSONL shards and published ZIP keys. It describes opaque partial bytes,
/// not a complete shard or archive. An ETag is a validator, not a local content digest.
public struct BulkRangeReference: Codable, Hashable, Sendable {
  /// The exact quoted strong entity tag, used unchanged in If-Match.
  public let entityTag: String
  /// The original unencoded S3 key.
  public let key: String
  /// Previously observed whole-representation length, independent of the requested range.
  public let totalByteCount: Int64
  /// A meaningful optional S3 version pin; literal null is refused.
  public let versionID: String?

  /// Encoded object path and optional version query on the fixed bulk origin.
  public var path: String {
    "/"
      + key.split(separator: "/").map { Endpoint<BulkRangeReceipt>.encoded(String($0)) }.joined(
        separator: "/")
      + (versionID.map { "?versionId=" + Endpoint<BulkRangeReceipt>.encoded($0) } ?? "")
  }
  /// The complete fixed-origin source URL.
  public var url: URL {
    guard let value = URL(string: Endpoint<BulkRangeReceipt>.origin + path) else {
      preconditionFailure("Validated range inputs form a source URL.")
    }
    return value
  }

  /// Creates a representation reference without fetching metadata or bytes.
  /// - Parameters:
  ///   - entityTag: One strong quoted ASCII ETag, not a wildcard, list or weak tag.
  ///   - key: A JSONL key under descriptions/authority-records, or a ZIP key under zip.
  ///   - totalByteCount: Positive whole-object byte length from prior source evidence.
  ///   - versionID: An optional nonempty version other than literal null.
  /// - Throws: `BulkRangeError.invalidReference` for malformed identity or path values.
  public init(entityTag: String, key: String, totalByteCount: Int64, versionID: String? = nil)
    throws(BulkRangeError)
  {
    let bytes = Array(entityTag.utf8)
    guard bytes.count >= 2, bytes.first == 34, bytes.last == 34,
      bytes.dropFirst().dropLast().allSatisfy({ $0 == 33 || (35...126).contains($0) }),
      totalByteCount > 0,
      (key.hasSuffix(".jsonl")
        && (key.hasPrefix("descriptions/") || key.hasPrefix("authority-records/")))
        || (key.hasPrefix("zip/") && key.hasSuffix(".zip")),
      !key.contains("\\"),
      !key.unicodeScalars.contains(where: { $0.value < 32 || $0.value == 127 }),
      !key.split(separator: "/", omittingEmptySubsequences: false).contains(where: {
        $0.isEmpty || $0 == "." || $0 == ".."
      }),
      versionID.map({
        !$0.isEmpty && $0 != "null"
          && !$0.unicodeScalars.contains(where: { $0.value < 32 || $0.value == 127 })
      }) ?? true
    else { throw .invalidReference }
    self.entityTag = entityTag
    self.key = key
    self.totalByteCount = totalByteCount
    self.versionID = versionID
  }

  /// Decodes source identity while repeating all constructor validation.
  /// - Parameter decoder: The stored representation to read.
  /// - Throws: A decoding error or the reference validation error.
  public init(from decoder: any Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    try self.init(
      entityTag: try c.decode(String.self, forKey: .entityTag),
      key: try c.decode(String.self, forKey: .key),
      totalByteCount: try c.decode(Int64.self, forKey: .totalByteCount),
      versionID: try c.decodeIfPresent(String.self, forKey: .versionID))
  }

  private enum CodingKeys: String, CodingKey {
    case entityTag
    case key
    case totalByteCount
    case versionID
  }

  package func receivedRange(
    contentRange: String?, entityTag: String?, requested: BulkByteRange, versionID: String?
  )
    throws(BulkRangeError) -> BulkByteRange
  {
    guard entityTag == self.entityTag, self.versionID == nil || versionID == self.versionID else {
      throw .representationChanged
    }
    guard let contentRange, contentRange.hasPrefix("bytes ") else { throw .invalidResponse }
    let parts = contentRange.dropFirst(6).split(separator: "/", omittingEmptySubsequences: false)
    guard parts.count == 2, let total = BulkByteRange.decimal(parts[1]) else {
      throw .invalidResponse
    }
    guard total == totalByteCount else { throw .representationChanged }
    let bounds = parts[0].split(separator: "-", omittingEmptySubsequences: false)
    guard bounds.count == 2, let lower = BulkByteRange.decimal(bounds[0]),
      let upper = BulkByteRange.decimal(bounds[1]), lower <= upper, upper < total
    else { throw .invalidResponse }
    let expected = try requested.clipped(to: totalByteCount)
    guard lower == expected.lowerBound, upper == expected.upperBound else { throw .invalidResponse }
    return expected
  }
}
