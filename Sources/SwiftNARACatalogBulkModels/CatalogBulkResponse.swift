#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// A value decoded from a bounded bulk response without a transport dependency.
///
/// Consumer types can conform to decode a custom representation from an endpoint.
public protocol CatalogBulkResponse: Sendable {
  /// Decodes one complete response body.
  /// - Parameter data: The original bounded response bytes.
  /// - Returns: The decoded response.
  /// - Throws: A source decoding failure.
  static func decode(_ data: Data) throws(CatalogDecodingError) -> Self
}
