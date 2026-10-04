#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// An authority record, such as a person, organization, topical subject, geographic place name, or
/// specific records type.
///
/// An authority record projects the source `record` object of a bulk envelope whose `recordType`
/// is `authority`. Authority records carry a `heading` rather than a description title or level of
/// description. Headings, names, notes, and references are the source's own description of the
/// entity, not a canonical identity: nothing is merged by name, matched to another provider, or
/// resolved across records. A reference keeps the exact NAID the source supplies even when no
/// record for that NAID has been read, and nothing is fetched to resolve it. Array order is the
/// source order.
///
/// ```swift
/// for try await line in try CatalogLineSequence(shard: receipt) {
///   guard let authority = line.record.authorityRecord else { continue }
///   print(authority.naID, authority.authorityType?.rawValue, authority.heading)
///   print(authority.birthDate?.year, authority.broaderTerms?.first?.naID)
/// }
/// ```
///
/// Members vary by category: the recorded bulk exports carry `biographicalNote`, `birthDate`,
/// `deathDate`, `name`, and `variantPersonNames` on person records, `administrativeHistoryNote`,
/// `jurisdictions`, and `organizationNames` on organization records, and `useFor`,
/// `narrowerTerms`, and `relatedTerms` on topical subject records. Any category can supply any
/// member. All source members, including unprojected ones such as `linkCounts` and `role`, remain
/// in `source`, and `CatalogLine.rawBytes` remains the byte-exact authority. Absent, null, and
/// wrong-shaped members project to nil; inspect `source` to distinguish them.
public struct CatalogAuthorityRecord: Codable, Hashable, Sendable {
  /// Every source member of the record object, or the non-object value the source supplied instead.
  public let source: JSONValue
  /// Creates a projection over any source value without changing it.
  ///
  /// The initializer does not check `recordType`; `CatalogRecord.authorityRecord` applies that
  /// check.
  ///
  /// - Parameter source: The source record object; a non-object projects every member as nil.
  public init(source: JSONValue) { self.source = source }
  /// The source administrative history note, only when the source supplies it as a string.
  public var administrativeHistoryNote: String? { source["administrativeHistoryNote"]?.string }
  /// The source authority type, only when the source supplies it as a string.
  public var authorityType: CatalogAuthorityType? {
    source["authorityType"]?.string.map(CatalogAuthorityType.init(rawValue:))
  }
  /// The source biographical note, only when the source supplies it as a string.
  public var biographicalNote: String? { source["biographicalNote"]?.string }
  /// The source birth date with its source precision, only when the source supplies a date object.
  ///
  /// The date is the source's own statement with only the components it supplies; it is never
  /// normalized or completed from another record.
  public var birthDate: CatalogDate? {
    source.objectMember("birthDate").map(CatalogDate.init(source:))
  }
  /// The source broader terms in source order, only when the source supplies an array.
  public var broaderTerms: [CatalogNAIDReference]? { references("broaderTerms") }
  /// The source death date with its source precision, only when the source supplies a date object.
  ///
  /// The date is the source's own statement with only the components it supplies; it is never
  /// normalized or completed from another record.
  public var deathDate: CatalogDate? {
    source.objectMember("deathDate").map(CatalogDate.init(source:))
  }
  /// The source heading, such as `Aaron, David L., 1938-`, only when supplied as a string.
  public var heading: String? { source["heading"]?.string }
  /// The source `preferred` flag, only when the source supplies a Boolean.
  ///
  /// Nil means the member is absent, null, or another shape; some recorded organization records
  /// omit it. Inspect `source` to distinguish them.
  public var isPreferred: Bool? {
    if case .bool(let value) = source["preferred"] { value } else { nil }
  }
  /// The source jurisdictions in source order, only when the source supplies an array.
  public var jurisdictions: [CatalogNAIDReference]? { references("jurisdictions") }
  /// The exact National Archives identifier, without floating-point conversion.
  public var naID: String? { source["naId"]?.identifier }
  /// The source name, only when the source supplies it as a string.
  public var name: String? { source["name"]?.string }
  /// The source narrower terms in source order, only when the source supplies an array.
  public var narrowerTerms: [CatalogNAIDReference]? { references("narrowerTerms") }
  /// The source organization names, unchanged, only when the source supplies an array.
  ///
  /// Each element carries its own heading, name, identifier, dates, and roles in the recorded
  /// exports; the elements are not modeled.
  public var organizationNames: [JSONValue]? { source["organizationNames"]?.array }
  /// The source organizational references in source order, only when the source supplies an array.
  public var organizationalReferences: [CatalogNAIDReference]? {
    references("organizationalReferences")
  }
  /// The source personal references in source order, only when the source supplies an array.
  public var personalReferences: [CatalogNAIDReference]? { references("personalReferences") }
  /// The source record type, such as `authority`, only when the source supplies a string.
  public var recordType: String? { source["recordType"]?.string }
  /// The source related terms in source order, only when the source supplies an array.
  public var relatedTerms: [CatalogNAIDReference]? { references("relatedTerms") }
  /// The source scope note, only when the source supplies it as a string.
  public var scopeNote: String? { source["scopeNote"]?.string }
  /// The source notes in source order.
  ///
  /// The recorded exports supply only strings. The array is projected only when every element is
  /// a string; if any element has another shape, the whole projection is nil rather than a partial
  /// list. Inspect `source` for the raw array.
  public var sourceNotes: [String]? { strings("sourceNotes") }
  /// The source terms this heading is used for, in source order.
  ///
  /// The recorded exports supply only strings. The array is projected only when every element is
  /// a string; if any element has another shape, the whole projection is nil rather than a partial
  /// list. Inspect `source` for the raw array.
  public var useFor: [String]? { strings("useFor") }
  /// The source variant person names, unchanged, only when the source supplies an array.
  public var variantPersonNames: [JSONValue]? { source["variantPersonNames"]?.array }

  /// Projects every element of a reference array in its source position.
  private func references(_ key: String) -> [CatalogNAIDReference]? {
    source[key]?.array?.map(CatalogNAIDReference.init(source:))
  }

  /// Projects an array only when every element is a string.
  private func strings(_ key: String) -> [String]? {
    guard let values = source[key]?.array else { return nil }
    var strings: [String] = []
    for value in values {
      guard let string = value.string else { return nil }
      strings.append(string)
    }
    return strings
  }
}

/// An extensible Catalog authority type code.
///
/// The constants name the authority type spellings the Catalog bulk exports contain. The provider
/// can supply others, and every value is retained exactly in `rawValue`. The Catalog API schema
/// documents a different, display representation such as `Person` and `Topical Subject`; such a
/// value is retained as its own raw value and is not equal to the corresponding constant.
///
/// ```swift
/// let type = CatalogAuthorityType(rawValue: "topicalSubject")
/// print(type == .topicalSubject)
/// ```
public struct CatalogAuthorityType: Codable, Hashable, RawRepresentable, Sendable {
  /// The Catalog bulk `geographicPlaceName` authority type.
  public static let geographicPlaceName = Self(rawValue: "geographicPlaceName")

  /// The Catalog bulk `organization` authority type.
  public static let organization = Self(rawValue: "organization")

  /// The Catalog bulk `person` authority type.
  public static let person = Self(rawValue: "person")

  /// The Catalog bulk `specificRecordsType` authority type.
  public static let specificRecordsType = Self(rawValue: "specificRecordsType")

  /// The Catalog bulk `topicalSubject` authority type.
  public static let topicalSubject = Self(rawValue: "topicalSubject")

  /// The source's exact authority type string.
  public let rawValue: String

  /// Creates an authority type without restricting future provider values.
  ///
  /// - Parameter rawValue: The exact authority type string.
  public init(rawValue: String) { self.rawValue = rawValue }

  /// Decodes the exact authority type string.
  ///
  /// - Parameter decoder: The decoder to read.
  /// - Throws: `DecodingError` for a non-string value.
  public init(from decoder: any Decoder) throws {
    rawValue = try decoder.singleValueContainer().decode(String.self)
  }

  /// Encodes the exact authority type string.
  ///
  /// - Parameter encoder: The encoder to write.
  /// - Throws: Any error from the encoder.
  public func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(rawValue)
  }
}

/// A source reference to another Catalog record by its National Archives identifier.
///
/// Authority records refer to related authorities through arrays of objects with a `naId` and a
/// `heading`, such as `broaderTerms` and `organizationalReferences`. The reference keeps the exact
/// identifier and heading the source supplies. Nothing is fetched, and the referenced record need
/// not exist in any file that has been read.
///
/// ```swift
/// for term in authority.broaderTerms ?? [] {
///   print(term.naID, term.heading)
/// }
/// ```
///
/// All source members, including unknown ones, remain in `source`. Absent, null, and wrong-shaped
/// members project to nil; inspect `source` to distinguish them.
public struct CatalogNAIDReference: Codable, Hashable, Sendable {
  /// Every source member of the reference, or the non-object value the source supplied instead.
  public let source: JSONValue
  /// Creates a projection over any source value without changing it.
  ///
  /// - Parameter source: The source reference value; a non-object projects every member as nil.
  public init(source: JSONValue) { self.source = source }
  /// The source heading of the referenced record, only when supplied as a string.
  public var heading: String? { source["heading"]?.string }
  /// The exact National Archives identifier, without floating-point conversion.
  public var naID: String? { source["naId"]?.identifier }
}
