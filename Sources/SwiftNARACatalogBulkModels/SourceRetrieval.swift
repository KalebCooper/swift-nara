#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// HTTP provenance for the exact response used by an operation.
///
/// Retrieval time comes from the caller's injected clock; it is not a publication time.
public struct SourceRetrieval: Codable, Hashable, Sendable {
  /// Every received header, including version hints and media type.
  public let headers: [SourceHeader]
  /// The caller-supplied retrieval instant sampled when the response is received.
  public let retrievedAt: Date
  /// The received HTTP status.
  public let status: Int
  /// The exact requested URL. Redirects are refused.
  public let url: URL
  /// Creates a retrieval receipt.
  public init(headers: [SourceHeader], retrievedAt: Date, status: Int, url: URL) {
    self.headers = headers; self.retrievedAt = retrievedAt; self.status = status; self.url = url
  }
}
