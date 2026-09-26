#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// A source date with its original components, without an invented instant.
///
/// The Catalog records a date as separate `day`, `month`, and `year` members plus a `logicalDate`
/// string. Only the components the source supplies are projected: a year-only date projects
/// `year` while `day` and `month` are nil. The `logicalDate` string fills missing components, so a
/// January 1 or December 31 logical date does not prove day precision; use the components to judge
/// precision. Nothing is converted to a calendar, time zone, or `Date`.
///
/// ```swift
/// let date = CatalogDate(source: record.fields["productionDates"]?.array?.first ?? .null)
/// print(date.year, date.month, date.day, date.logicalDate)
/// ```
///
/// All source members, including unknown ones, remain in `source`. Absent, null, and wrong-shaped
/// members project to nil; inspect `source` to distinguish them.
public struct CatalogDate: Codable, Hashable, Sendable {
  /// Every source member of the date, or the non-object value the source supplied instead.
  public let source: JSONValue
  /// Creates a projection over any source value without changing it.
  ///
  /// - Parameter source: The source date value; a non-object projects every component as nil.
  public init(source: JSONValue) { self.source = source }
  /// The source day of month, only when the source supplies it as an exact integer.
  public var day: Int? { source["day"]?.exactInteger }
  /// The source logical date string, such as `1816-04-08`, without parsing it.
  public var logicalDate: String? { source["logicalDate"]?.string }
  /// The source month, only when the source supplies it as an exact integer.
  public var month: Int? { source["month"]?.exactInteger }
  /// The source year, only when the source supplies it as an exact integer.
  public var year: Int? { source["year"]?.exactInteger }
}
