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
  /// The typed archival description view, only when the source `recordType` is exactly
  /// `description`.
  ///
  /// Authority, contribution, unknown, missing, and non-string record types return nil; their
  /// members remain available through `fields` and `source`.
  public var archivalDescription: CatalogDescription? {
    fields["recordType"] == .string("description") ? CatalogDescription(source: fields) : nil
  }
  /// The typed authority record view, only when the source `recordType` is exactly `authority`.
  ///
  /// Description, contribution, unknown, missing, and non-string record types return nil; their
  /// members remain available through `fields` and `source`.
  public var authorityRecord: CatalogAuthorityRecord? {
    fields["recordType"] == .string("authority") ? CatalogAuthorityRecord(source: fields) : nil
  }
  /// The source public comments from the envelope's top-level `record_comment` array, in source
  /// order, only when the source supplies an array.
  ///
  /// Every element keeps its position, including a non-object element whose members project as
  /// nil. Comments are attributed contributions, not archival description or OCR.
  public var comments: [CatalogContribution]? { contributions("record_comment") }
  /// The source contribution metadata arrays, kept separate from the contributions and from each
  /// other.
  public var contributionMetadata: CatalogContributionMetadata {
    CatalogContributionMetadata(source: source)
  }
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
  /// The source public tags from the envelope's top-level `record_tag` array, in source order,
  /// only when the source supplies an array.
  ///
  /// Every element keeps its position, including a non-object element whose members project as
  /// nil. Tags are attributed contributions, not archival subjects or classifications.
  public var tags: [CatalogContribution]? { contributions("record_tag") }
  /// The source title, without normalizing historical dates or scope.
  public var title: String? { fields["title"]?.string }
  /// The source public transcriptions from the envelope's top-level `record_transcription` array,
  /// in source order, only when the source supplies an array.
  ///
  /// Every element keeps its position, including a non-object element whose members project as
  /// nil. A transcription is attributed contributed text. It does not replace a digital object's
  /// `extractedText` OCR, and neither one is certified original text.
  public var transcriptions: [CatalogContribution]? { contributions("record_transcription") }
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

  /// Projects every element of a top-level contribution array in its source position.
  private func contributions(_ key: String) -> [CatalogContribution]? {
    source[key]?.array?.map(CatalogContribution.init(source:))
  }
}
