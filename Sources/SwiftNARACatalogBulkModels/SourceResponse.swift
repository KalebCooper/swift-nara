#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// A decoded value and the exact bounded source bytes from the same HTTP response.
public struct SourceResponse<Value: Sendable>: Sendable {
  /// Original response bytes, without re-encoding the decoded value.
  public let body: Data
  /// Request and response provenance.
  public let retrieval: SourceRetrieval
  /// The decoded source value.
  public let value: Value
  /// Creates a captured response.
  public init(body: Data, retrieval: SourceRetrieval, value: Value) {
    self.body = body; self.retrieval = retrieval; self.value = value
  }
}
