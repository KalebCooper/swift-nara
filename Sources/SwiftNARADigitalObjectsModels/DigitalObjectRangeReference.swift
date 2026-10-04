/// A known original digital-object representation selected by strong ETag and length.
///
/// The original reference preserves archival identifiers and URL mapping. ETags are
/// validators, not local digests. IIIF derivatives and literal null S3 versions are not
/// treated as immutable original identities.
public struct DigitalObjectRangeReference: Codable, Hashable, Sendable {
  /// Exact strong quoted entity tag used unchanged in If-Match.
  public let entityTag: String
  /// Original archival identity and validated media transport path.
  public let object: DigitalObjectReference
  /// Previously observed length of the complete original representation.
  public let totalByteCount: Int64

  /// Creates a reference without retrieving metadata or bytes.
  /// - Parameters:
  ///   - entityTag: One strong quoted ASCII ETag, not a wildcard or list.
  ///   - object: An original digital-object reference on an accepted media prefix.
  ///   - totalByteCount: Positive whole-object length from prior source evidence.
  /// - Throws: `DigitalObjectRangeError.invalidReference` for an invalid validator or length.
  public init(entityTag: String, object: DigitalObjectReference, totalByteCount: Int64)
    throws(DigitalObjectRangeError)
  {
    let bytes = Array(entityTag.utf8)
    guard bytes.count >= 2, bytes.first == 34, bytes.last == 34,
      bytes.dropFirst().dropLast().allSatisfy({ $0 == 33 || (35...126).contains($0) }),
      totalByteCount > 0
    else { throw .invalidReference }
    self.entityTag = entityTag
    self.object = object
    self.totalByteCount = totalByteCount
  }

  /// Decodes source identity while repeating all constructor validation.
  /// - Parameter decoder: The stored representation to read.
  /// - Throws: A decoding error or the reference validation error.
  public init(from decoder: any Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    try self.init(
      entityTag: try c.decode(String.self, forKey: .entityTag),
      object: try c.decode(DigitalObjectReference.self, forKey: .object),
      totalByteCount: try c.decode(Int64.self, forKey: .totalByteCount))
  }

  private enum CodingKeys: String, CodingKey {
    case entityTag
    case object
    case totalByteCount
  }

  package func receivedRange(
    contentRange: String?, entityTag: String?, requested: DigitalObjectByteRange
  )
    throws(DigitalObjectRangeError) -> DigitalObjectByteRange
  {
    guard entityTag == self.entityTag else {
      throw .representationChanged
    }
    guard let contentRange, contentRange.hasPrefix("bytes ") else { throw .invalidResponse }
    let parts = contentRange.dropFirst(6).split(separator: "/", omittingEmptySubsequences: false)
    guard parts.count == 2, let total = DigitalObjectByteRange.decimal(parts[1]) else {
      throw .invalidResponse
    }
    guard total == totalByteCount else { throw .representationChanged }
    let bounds = parts[0].split(separator: "-", omittingEmptySubsequences: false)
    guard bounds.count == 2, let lower = DigitalObjectByteRange.decimal(bounds[0]),
      let upper = DigitalObjectByteRange.decimal(bounds[1]), lower <= upper, upper < total
    else { throw .invalidResponse }
    let expected = try requested.clipped(to: totalByteCount)
    guard lower == expected.lowerBound, upper == expected.upperBound else { throw .invalidResponse }
    return expected
  }
}
