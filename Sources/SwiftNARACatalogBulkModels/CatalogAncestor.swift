#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// A source ancestor of an archival description, such as its record group, series, or file unit.
///
/// The Catalog lists a description's ancestors in its `ancestors` array, each with a `distance`
/// counting the hierarchy levels between the ancestor and the description. Projections read the
/// ancestor's own members only: its inclusive dates describe the ancestor, not the description, and
/// are never propagated onto a descendant. Array order is the source order; nothing is sorted by
/// distance.
///
/// ```swift
/// for ancestor in record.ancestors?.map(CatalogAncestor.init(source:)) ?? [] {
///   print(ancestor.distance, ancestor.levelOfDescription?.rawValue, ancestor.naID, ancestor.title)
/// }
/// ```
///
/// All source members, including unknown ones, remain in `source`. Absent, null, and wrong-shaped
/// members project to nil; inspect `source` to distinguish them.
public struct CatalogAncestor: Codable, Hashable, Sendable {
  /// Every source member of the ancestor, or the non-object value the source supplied instead.
  public let source: JSONValue
  /// Creates a projection over any source value without changing it.
  ///
  /// - Parameter source: The source ancestor value; a non-object projects every member as nil.
  public init(source: JSONValue) { self.source = source }
  /// The source collection identifier, such as `FDR-FDRMSF`, only when supplied as a string.
  public var collectionIdentifier: String? { source["collectionIdentifier"]?.string }
  /// The source creators, unchanged, only when the source supplies an array.
  public var creators: [JSONValue]? { source["creators"]?.array }
  /// The number of hierarchy levels between the ancestor and the description, only when the
  /// source supplies it as an exact integer.
  public var distance: Int? { source["distance"]?.exactInteger }
  /// The ancestor's own inclusive end date, only when the source supplies a date object.
  public var inclusiveEndDate: CatalogDate? {
    source.objectMember("inclusiveEndDate").map(CatalogDate.init(source:))
  }
  /// The ancestor's own inclusive start date, only when the source supplies a date object.
  public var inclusiveStartDate: CatalogDate? {
    source.objectMember("inclusiveStartDate").map(CatalogDate.init(source:))
  }
  /// The source level of description, only when the source supplies it as a string.
  public var levelOfDescription: CatalogDescriptionLevel? {
    source["levelOfDescription"]?.string.map(CatalogDescriptionLevel.init(rawValue:))
  }
  /// The exact National Archives identifier, without floating-point conversion.
  public var naID: String? { source["naId"]?.identifier }
  /// The source record group number, only when the source supplies it as an exact integer.
  public var recordGroupNumber: Int? { source["recordGroupNumber"]?.exactInteger }
  /// The source title, only when the source supplies it as a string.
  public var title: String? { source["title"]?.string }
}

/// An extensible Catalog level of description code.
///
/// The constants name the level spellings the Catalog bulk exports contain. The provider can supply
/// others, and every value is retained exactly in `rawValue`. The Catalog API schema documents a
/// different, display representation such as `Record Group` and `File Unit`; such a value is
/// retained as its own raw value and is not equal to the corresponding constant.
///
/// ```swift
/// let level = CatalogDescriptionLevel(rawValue: "fileUnit")
/// print(level == .fileUnit)
/// ```
public struct CatalogDescriptionLevel: Codable, Hashable, RawRepresentable, Sendable {
  /// The Catalog bulk `collection` level.
  public static let collection = Self(rawValue: "collection")

  /// The Catalog bulk `fileUnit` level.
  public static let fileUnit = Self(rawValue: "fileUnit")

  /// The Catalog bulk `item` level.
  public static let item = Self(rawValue: "item")

  /// The Catalog bulk `recordGroup` level.
  public static let recordGroup = Self(rawValue: "recordGroup")

  /// The Catalog bulk `series` level.
  public static let series = Self(rawValue: "series")

  /// The source's exact level string.
  public let rawValue: String

  /// Creates a level without restricting future provider values.
  ///
  /// - Parameter rawValue: The exact level string.
  public init(rawValue: String) { self.rawValue = rawValue }

  /// Decodes the exact level string.
  ///
  /// - Parameter decoder: The decoder to read.
  /// - Throws: `DecodingError` for a non-string value.
  public init(from decoder: any Decoder) throws {
    rawValue = try decoder.singleValueContainer().decode(String.self)
  }

  /// Encodes the exact level string.
  ///
  /// - Parameter encoder: The encoder to write.
  /// - Throws: Any error from the encoder.
  public func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(rawValue)
  }
}
