#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// An archival description, such as an item, file unit, series, collection, or record group.
///
/// A description projects the source `record` object of a bulk envelope whose `recordType` is
/// `description`. Projections read the description's own members only. Ancestor dates describe the
/// ancestor and are never propagated onto the description, and nothing is reconciled or
/// deduplicated across records: the same ancestor can carry different values on different records,
/// as the record group 11 ancestor does with end dates of `2006-01-01` and `2006-12-31`, and each
/// value is retained as its record supplies it. Array order is the source order.
///
/// ```swift
/// for try await line in try CatalogLineSequence(shard: receipt) {
///   guard let description = line.record.archivalDescription else { continue }
///   print(description.naID, description.levelOfDescription?.rawValue, description.title)
///   print(description.productionDates?.first?.year, description.ancestors?.first?.naID)
///   print(description.accessRestriction?.status?.rawValue)
/// }
/// ```
///
/// All source members, including unknown ones, remain in `source`, and `CatalogLine.rawBytes`
/// remains the byte-exact authority. Absent, null, and wrong-shaped members project to nil; inspect
/// `source` to distinguish them.
public struct CatalogDescription: Codable, Hashable, Sendable {
  /// Every source member of the record object, or the non-object value the source supplied instead.
  public let source: JSONValue
  /// Creates a projection over any source value without changing it.
  ///
  /// The initializer does not check `recordType`; `CatalogRecord.archivalDescription` applies that
  /// check.
  ///
  /// - Parameter source: The source record object; a non-object projects every member as nil.
  public init(source: JSONValue) { self.source = source }
  /// The description's access restriction, only when the source supplies an object.
  public var accessRestriction: CatalogRestriction? {
    source.objectMember("accessRestriction").map(CatalogRestriction.init(source:))
  }
  /// The description's ancestors in source order, only when the source supplies an array.
  ///
  /// Every element is projected in its source position, and each ancestor retains its element in
  /// `source`; a non-object element projects every member as nil.
  public var ancestors: [CatalogAncestor]? {
    source["ancestors"]?.array?.map(CatalogAncestor.init(source:))
  }
  /// The source general records types, such as `Textual Records`, in source order.
  ///
  /// The array is projected only when every element is a string; if any element has another
  /// shape, the whole projection is nil rather than a partial list. Inspect `source` for the raw
  /// array.
  public var generalRecordsTypes: [String]? {
    guard let values = source["generalRecordsTypes"]?.array else { return nil }
    var strings: [String] = []
    for value in values {
      guard let string = value.string else { return nil }
      strings.append(string)
    }
    return strings
  }
  /// The description's own inclusive end date, only when the source supplies a date object.
  public var inclusiveEndDate: CatalogDate? {
    source.objectMember("inclusiveEndDate").map(CatalogDate.init(source:))
  }
  /// The description's own inclusive start date, only when the source supplies a date object.
  public var inclusiveStartDate: CatalogDate? {
    source.objectMember("inclusiveStartDate").map(CatalogDate.init(source:))
  }
  /// The source level of description, only when the source supplies it as a string.
  public var levelOfDescription: CatalogDescriptionLevel? {
    source["levelOfDescription"]?.string.map(CatalogDescriptionLevel.init(rawValue:))
  }
  /// The exact National Archives identifier, without floating-point conversion.
  public var naID: String? { source["naId"]?.identifier }
  /// The source physical occurrences, unchanged, only when the source supplies an array.
  ///
  /// Physical occurrences are not modeled. A physical restriction on handling or use of a
  /// particular medium is recorded as `physicalRestrictionNote` inside each occurrence's
  /// `mediaOccurrences` array, as in
  /// `physicalOccurrences[0]["mediaOccurrences"]?.array?[0]["physicalRestrictionNote"]`; it is
  /// separate from `accessRestriction` and `useRestriction`.
  public var physicalOccurrences: [JSONValue]? { source["physicalOccurrences"]?.array }
  /// The description's production dates in source order, only when the source supplies an array.
  ///
  /// Every element is projected in its source position, and each date retains its element in
  /// `source`; a non-object element projects every component as nil.
  public var productionDates: [CatalogDate]? {
    source["productionDates"]?.array?.map(CatalogDate.init(source:))
  }
  /// The source record type, such as `description`, only when the source supplies a string.
  public var recordType: String? { source["recordType"]?.string }
  /// The source scope and content note, only when the source supplies it as a string.
  public var scopeAndContentNote: String? { source["scopeAndContentNote"]?.string }
  /// The source title, without normalizing historical dates or scope.
  public var title: String? { source["title"]?.string }
  /// The description's use restriction, only when the source supplies an object.
  public var useRestriction: CatalogRestriction? {
    source.objectMember("useRestriction").map(CatalogRestriction.init(source:))
  }
}
