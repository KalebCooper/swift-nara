#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// A source HTTP header, preserving order and duplicate field names.
public struct SourceHeader: Codable, Hashable, Sendable {
  /// The received field name.
  public let name: String
  /// The received field value.
  public let value: String
  /// Creates a source header.
  public init(name: String, value: String) { self.name = name; self.value = value }
}
