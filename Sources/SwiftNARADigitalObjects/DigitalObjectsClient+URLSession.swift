#if canImport(Darwin)
import Foundation
import HTTPURLSession

extension DigitalObjectsClient {
  /// Creates a client using an Apple URL session.
  /// - Parameters:
  ///   - configuration: Explicit caller identity and byte budgets.
  ///   - retrievalTime: Injected receipt instants.
  ///   - session: The URL session used by the streaming transport.
  public init(
    configuration: DigitalObjectsConfiguration, retrievalTime: @escaping @Sendable () -> Date,
    session: URLSession = .shared
  ) {
    self.init(
      configuration: configuration, retrievalTime: retrievalTime,
      transport: URLSessionTransport(session: session))
  }
}
#endif
