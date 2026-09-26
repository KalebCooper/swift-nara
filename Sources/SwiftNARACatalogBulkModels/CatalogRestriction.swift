#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// A source access or use restriction, without interpreting it as permission to reuse.
///
/// The Catalog records `accessRestriction` and `useRestriction` as objects with a `status` string
/// and an optional `note`. The status is an open provider code, not a reuse authorization: an
/// `Unrestricted` status does not grant rights the source does not state, and an unknown status is
/// retained rather than rejected. The specific restriction arrays (`specificAccessRestrictions` and
/// `specificUseRestrictions`) and any unknown members are not projected; they remain in `source`.
///
/// ```swift
/// if let access = record.accessRestriction {
///   let restriction = CatalogRestriction(source: access)
///   print(restriction.status?.rawValue, restriction.note)
/// }
/// ```
///
/// Absent, null, and wrong-shaped members project to nil; inspect `source` to distinguish them.
public struct CatalogRestriction: Codable, Hashable, Sendable {
  /// Every source member of the restriction, or the non-object value the source supplied instead.
  public let source: JSONValue
  /// Creates a projection over any source value without changing it.
  ///
  /// - Parameter source: The source restriction value; a non-object projects every member as nil.
  public init(source: JSONValue) { self.source = source }
  /// The source restriction note, only when the source supplies it as a string.
  public var note: String? { source["note"]?.string }
  /// The source restriction status, only when the source supplies it as a string.
  public var status: CatalogRestrictionStatus? {
    source["status"]?.string.map(CatalogRestrictionStatus.init(rawValue:))
  }
}

/// An extensible Catalog restriction status code.
///
/// The constants name status values the Catalog documents or the recorded bulk exports contain;
/// the provider can supply others, and every value is retained exactly in `rawValue`. A status
/// states what the source declares about restrictions; it is not a reuse authorization.
///
/// ```swift
/// let status = CatalogRestrictionStatus(rawValue: "Restricted - Partly")
/// print(status == .restrictedPartly)
/// ```
public struct CatalogRestrictionStatus: Codable, Hashable, RawRepresentable, Sendable {
  /// The Catalog `Restricted - Fully` status.
  public static let restrictedFully = Self(rawValue: "Restricted - Fully")

  /// The Catalog `Restricted - Partly` status.
  public static let restrictedPartly = Self(rawValue: "Restricted - Partly")

  /// The Catalog `Restricted - Possibly` status.
  public static let restrictedPossibly = Self(rawValue: "Restricted - Possibly")

  /// The Catalog `Unrestricted` status.
  public static let unrestricted = Self(rawValue: "Unrestricted")

  /// The source's exact status string.
  public let rawValue: String

  /// Creates a status without restricting future provider values.
  ///
  /// - Parameter rawValue: The exact status string.
  public init(rawValue: String) { self.rawValue = rawValue }

  /// Decodes the exact status string.
  ///
  /// - Parameter decoder: The decoder to read.
  /// - Throws: `DecodingError` for a non-string value.
  public init(from decoder: any Decoder) throws {
    rawValue = try decoder.singleValueContainer().decode(String.self)
  }

  /// Encodes the exact status string.
  ///
  /// - Parameter encoder: The encoder to write.
  /// - Throws: Any error from the encoder.
  public func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(rawValue)
  }
}
