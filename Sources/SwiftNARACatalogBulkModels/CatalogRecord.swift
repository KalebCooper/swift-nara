#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// An archival description or authority record with its complete open source envelope.
///
/// All original members, nulls, and unknown values remain in `source`. Projections never filter
/// campaign material or infer presidential-office classification from a title.
public struct CatalogRecord: Codable, Hashable, Sendable {
  /// The entire JSONL envelope, including unknown top-level fields.
  public let source: JSONValue

  /// Decodes and validates the source envelope and its exact NAID.
  public init(from decoder: any Decoder) throws {
    let source = try JSONValue(from: decoder)
    guard source["record"]?.object != nil, let identifier = source["record"]?["naId"]?.identifier,
      !identifier.isEmpty
    else {
      throw DecodingError.dataCorrupted(
        .init(
          codingPath: decoder.codingPath, debugDescription: "A bulk record requires record.naId."))
    }
    self.source = source
  }

  /// Access restrictions, including all notes and unknown fields.
  public var accessRestriction: JSONValue? { fields["accessRestriction"] }
  /// Source ancestors in source order, retaining distance and classification evidence.
  public var ancestors: [JSONValue]? { fields["ancestors"]?.array }
  /// Source digital objects. Nil means absent, null, or a different shape; inspect `fields` to distinguish them.
  public var digitalObjects: [CatalogDigitalObject]? {
    fields["digitalObjects"]?.array.map { $0.map { CatalogDigitalObject(source: $0) } }
  }
  /// The complete record object; use this for optional hierarchy, dates, rights, or future fields.
  public var fields: JSONValue { source["record"] ?? .null }
  /// True only for an explicitly empty digital-object array; nil means availability was not declared.
  public var isMetadataOnly: Bool? { digitalObjects.map(\.isEmpty) }
  /// The open provider level, such as item, fileUnit, series, or collection.
  public var levelOfDescription: String? { fields["levelOfDescription"]?.string }
  /// The exact National Archives identifier, without floating-point conversion.
  public var naID: String { fields["naId"]?.identifier ?? "" }
  /// The source title, without normalizing historical dates or scope.
  public var title: String? { fields["title"]?.string }
  /// Use restrictions, including rights statements and unknown fields.
  public var useRestriction: JSONValue? { fields["useRestriction"] }

  /// Decodes one bounded JSON record, independent of transport or file iteration.
  /// - Parameters:
  ///   - data: One UTF-8 JSONL record, optionally followed by its line terminator.
  ///   - maximumBytes: Maximum record bytes; defaults to 8 MiB.
  /// - Returns: A source record retaining every JSON field.
  /// - Throws: `CatalogDecodingError.limitExceeded` or `.malformedJSON`.
  public static func decode(_ data: Data, maximumBytes: Int = 8 * 1024 * 1024)
    throws(CatalogDecodingError) -> Self
  {
    guard maximumBytes > 0, data.count <= maximumBytes else { throw .limitExceeded }
    do { return try JSONDecoder().decode(Self.self, from: data) } catch { throw .malformedJSON }
  }

  /// Encodes the original JSON value without dropping unknown members.
  public func encode(to encoder: any Encoder) throws { try source.encode(to: encoder) }
}
