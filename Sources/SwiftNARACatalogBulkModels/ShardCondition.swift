#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// One conditional validator for a shard download, holding a single entity tag.
///
/// The entity tag is kept exactly as supplied, including its quotes and any `W/` prefix, and is
/// not parsed further. A condition names one validator only: the wildcard `*` and comma-separated
/// lists are rejected, and no combination of validators is expressible. An entity tag is a version
/// hint from the source, not a content digest.
/// ```swift
/// let condition = try ShardCondition.ifNoneMatch("\"4ee6006efb1a7923711c088aaf8626a0\"")
/// print(condition.fieldName)  // If-None-Match
/// ```
public struct ShardCondition: Hashable, Sendable {
  /// The HTTP precondition a validator expresses.
  public enum Kind: Hashable, Sendable {
    /// Download only while the current object still carries the entity tag.
    case ifMatch
    /// Download only when the current object no longer carries the entity tag.
    case ifNoneMatch
  }

  /// The entity tag, exactly as supplied.
  public let etag: String
  /// The precondition sent with the entity tag.
  public let kind: Kind

  /// The HTTP header field name for this condition, `If-Match` or `If-None-Match`.
  public var fieldName: String {
    switch kind {
    case .ifMatch: "If-Match"
    case .ifNoneMatch: "If-None-Match"
    }
  }

  /// Creates a condition from one entity tag without sending a request.
  /// - Parameters:
  ///   - etag: A single entity tag, kept exactly, such as `"4ee6006efb1a7923711c088aaf8626a0"`.
  ///   - kind: The precondition to send.
  /// - Throws: `ManifestError.invalidQuery` when the entity tag is empty, contains a control
  ///   character or comma, is the wildcard `*`, or begins or ends with a space or tab.
  public init(etag: String, kind: Kind) throws(ManifestError) {
    guard let first = etag.unicodeScalars.first, let last = etag.unicodeScalars.last,
      first != " ", first != "\t", last != " ", last != "\t", etag != "*",
      !etag.unicodeScalars.contains(where: { $0.value < 32 || $0.value == 127 || $0 == "," })
    else { throw .invalidQuery }
    self.etag = etag; self.kind = kind
  }

  /// Creates a condition that downloads only while the object still carries the entity tag.
  ///
  /// A failed precondition means the selected object changed and needs renewed inventory.
  /// ```swift
  /// let condition = try ShardCondition.ifMatch("\"4ee6006efb1a7923711c088aaf8626a0\"")
  /// ```
  /// - Parameter etag: A single entity tag, kept exactly.
  /// - Returns: An `If-Match` condition.
  /// - Throws: `ManifestError.invalidQuery` for an invalid entity tag.
  public static func ifMatch(_ etag: String) throws(ManifestError) -> Self {
    try Self(etag: etag, kind: .ifMatch)
  }

  /// Creates a condition that downloads only when the object no longer carries the entity tag.
  ///
  /// An unchanged entity tag means no observed metadata change, not verified byte identity.
  /// ```swift
  /// let condition = try ShardCondition.ifNoneMatch("\"4ee6006efb1a7923711c088aaf8626a0\"")
  /// ```
  /// - Parameter etag: A single entity tag, kept exactly.
  /// - Returns: An `If-None-Match` condition.
  /// - Throws: `ManifestError.invalidQuery` for an invalid entity tag.
  public static func ifNoneMatch(_ etag: String) throws(ManifestError) -> Self {
    try Self(etag: etag, kind: .ifNoneMatch)
  }
}
