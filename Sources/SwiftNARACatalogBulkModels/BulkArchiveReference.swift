#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// One selected ZIP object in the public bulk bucket, independent of download budgets.
public struct BulkArchiveReference: Codable, Hashable, Sendable {
  /// The exact unencoded object key under zip/.
  public let key: String
  /// An optional meaningful S3 version pin, distinct from an ETag.
  public let versionID: String?

  /// The encoded path and optional version query.
  public var path: String {
    "/"
      + key.split(separator: "/").map { Endpoint<BulkArchiveReceipt>.encoded(String($0)) }.joined(
        separator: "/")
      + (versionID.map { "?versionId=" + Endpoint<BulkArchiveReceipt>.encoded($0) } ?? "")
  }
  /// The complete fixed-origin archive URL.
  public var url: URL {
    guard let value = URL(string: Endpoint<BulkArchiveReceipt>.origin + path) else {
      preconditionFailure("Validated archive keys form a source URL.")
    }
    return value
  }

  /// Selects an archive without listing, downloading, or parsing it.
  /// - Parameters:
  ///   - key: A published or discovered zip/*.zip key; no latest filename is assumed.
  ///   - versionID: A nonempty opaque version other than literal null, if known.
  /// - Throws: `ManifestError.invalidQuery` for invalid keys or versions.
  public init(key: String, versionID: String? = nil) throws(ManifestError) {
    guard key.hasPrefix("zip/"), key.hasSuffix(".zip"), !key.contains("\\"),
      !key.unicodeScalars.contains(where: { $0.value < 32 || $0.value == 127 }),
      !key.split(separator: "/", omittingEmptySubsequences: false).contains(where: {
        $0.isEmpty || $0 == "." || $0 == ".."
      }),
      versionID.map({
        !$0.isEmpty && $0 != "null"
          && !$0.unicodeScalars.contains(where: { $0.value < 32 || $0.value == 127 })
      }) ?? true
    else { throw .invalidQuery }
    self.key = key
    self.versionID = versionID
  }

  /// Decodes while repeating key and version validation.
  /// - Parameter decoder: Stored reference data.
  /// - Throws: A decoding or reference validation error.
  public init(from decoder: any Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    try self.init(
      key: c.decode(String.self, forKey: .key),
      versionID: c.decodeIfPresent(String.self, forKey: .versionID))
  }

  /// Adds previously observed identity for conditional ranges or durable resume.
  /// - Parameters:
  ///   - entityTag: A strong quoted ETag from source evidence.
  ///   - totalByteCount: The observed positive complete length.
  /// - Returns: A range reference retaining this key and version pin.
  /// - Throws: `BulkRangeError` for an invalid validator or length.
  public func rangeReference(entityTag: String, totalByteCount: Int64) throws(BulkRangeError)
    -> BulkRangeReference
  {
    try BulkRangeReference(
      entityTag: entityTag, key: key, totalByteCount: totalByteCount, versionID: versionID)
  }

  private enum CodingKeys: String, CodingKey {
    case key
    case versionID
  }
}
