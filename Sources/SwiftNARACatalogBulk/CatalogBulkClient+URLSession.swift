#if canImport(Darwin)
import Foundation
import HTTPURLSession

extension CatalogBulkClient {
  /// Creates a client using the supplied Apple URL session.
  /// - Parameters:
  ///   - configuration: Explicit application identity and byte bounds.
  ///   - retrievalTime: The injected wall-clock source for receipt instants.
  ///   - session: The session used by the transport.
  public init(
    configuration: CatalogBulkConfiguration, retrievalTime: @escaping @Sendable () -> Date,
    session: URLSession = .shared
  ) {
    self.init(
      configuration: configuration, retrievalTime: retrievalTime,
      transport: URLSessionTransport(session: session))
  }
}
#endif
