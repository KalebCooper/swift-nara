#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

import HTTPCore
import HTTPTypes
import SwiftNARACatalogBulkModels

/// A resource-bounded client for the official NARA Catalog bulk distribution.
///
/// This client never calls the separate Catalog HTTP API. Redirects are refused, requests are
/// unauthenticated, and retries are disabled. Local record iteration performs no networking.
/// ```swift
/// let query = try ManifestQuery(prefix: "descriptions/record-groups/rg_11/")
/// for try await object in client.objects(matching: query) { print(object.key) }
/// ```
public struct CatalogBulkClient: Sendable {
  let configuration: CatalogBulkConfiguration
  let http: HTTPClient
  let retrievalTime: @Sendable () -> Date

  /// Creates a client with explicit source identity and retrieval time.
  /// - Parameters:
  ///   - configuration: The identity and byte bounds.
  ///   - retrievalTime: An injected source of wall-clock receipt instants, sampled when the response is received.
  ///   - transport: The HTTP transport; it must not follow redirects internally.
  public init(
    configuration: CatalogBulkConfiguration, retrievalTime: @escaping @Sendable () -> Date,
    transport: any Transport
  ) {
    self.configuration = configuration
    self.retrievalTime = retrievalTime
    guard let baseURL = URL(string: Endpoint<BulkManifest>.origin) else {
      preconditionFailure("The fixed HTTPS bucket origin is valid.")
    }
    http = HTTPClient(
      baseURL: baseURL, defaultHeaders: [.userAgent: configuration.userAgent],
      redirectPolicy: .never,
      transport: BoundedTransport(base: transport, maximumBytes: configuration.maximumManifestBytes)
    )
  }

  /// Retrieves one manifest page through the reusable request executor.
  /// - Parameter query: The page to retrieve.
  /// - Returns: The original listing envelope.
  /// - Throws: `CatalogBulkError` for source, continuation, transport, or cancellation failures.
  public func manifest(matching query: ManifestQuery) async throws(CatalogBulkError) -> BulkManifest
  {
    try await value(for: .manifest(query))
  }

  /// Creates a lazy manifest traversal with no construction I/O or prefetch.
  /// - Parameter query: The initial query.
  /// - Returns: An independently iterable page sequence, retaining source bytes and receipts.
  public func manifestPages(matching query: ManifestQuery) -> ManifestPageSequence {
    pages(for: .manifest(query))
  }

  /// Creates an object traversal from a reusable manifest request.
  /// - Parameter request: A built-in query or a single endpoint without continuation.
  /// - Returns: A lazy sequence of unfiltered objects.
  public func objects(for request: CatalogBulkRequest<BulkManifest>) -> BulkObjectSequence {
    BulkObjectSequence(pages: pages(for: request))
  }

  /// Creates a lazy object traversal preserving order and duplicates.
  /// - Parameter query: The initial query.
  /// - Returns: Every source object, draining each page before fetching another.
  public func objects(matching query: ManifestQuery) -> BulkObjectSequence {
    objects(for: .manifest(query))
  }

  /// Creates a lazy manifest traversal with optional source recording.
  ///
  /// A recorder runs once per validated page before it is yielded. A failed recorder terminates
  /// that iterator without fetching another page. No recorder runs at sequence construction.
  /// - Parameters:
  ///   - request: The initial operation; custom endpoints yield exactly one page.
  ///   - record: An optional asynchronous persistence callback for exact bytes and provenance.
  /// - Returns: Independent, demand-driven traversals.
  public func pages(
    for request: CatalogBulkRequest<BulkManifest>,
    record: (@Sendable (SourceResponse<BulkManifest>) async throws -> Void)? = nil
  ) -> ManifestPageSequence {
    let endpoint = Self.endpoint(for: request)
    let query: ManifestQuery?
    if case .manifest(let value) = request.resolution { query = value } else { query = nil }
    let base = http.pages(
      Self.request(endpoint), as: ManifestCapture.self,
      decode: { response in
        ManifestCapture(
          body: response.body, manifest: try BulkManifest.decode(response.body),
          retrievedAt: retrievalTime())
      },
      next: { page, original in
        guard query != nil, page.value.manifest.isTruncated,
          let token = page.value.manifest.nextContinuationToken,
          let query,
          let next = try? ManifestQuery(
            continuationToken: token, maxKeys: query.maxKeys, prefix: query.prefix)
        else { return nil }
        return .request(Self.request(Endpoint<BulkManifest>.manifest(next)))
      })
    return ManifestPageSequence(base: base, endpoint: endpoint, query: query, record: record)
  }

  /// Captures a request's value and its exact response bytes in one exchange.
  /// - Parameter request: A source operation.
  /// - Returns: The decoded value and original HTTP evidence.
  /// - Throws: `CatalogBulkError` for decoding, pagination, transport, or cancellation failures.
  public func response<Value: CatalogBulkResponse>(for request: CatalogBulkRequest<Value>)
    async throws(CatalogBulkError) -> SourceResponse<Value>
  {
    try await response(to: Self.endpoint(for: request))
  }

  /// Captures one endpoint response without refetching for provenance.
  /// - Parameter endpoint: The validated source endpoint.
  /// - Returns: Exact bytes, headers, source URL, retrieval time, and the decoded value.
  /// - Throws: `CatalogBulkError` for decoding, transport, or cancellation failures.
  public func response<Value: CatalogBulkResponse>(to endpoint: Endpoint<Value>)
    async throws(CatalogBulkError) -> SourceResponse<Value>
  {
    guard !Task.isCancelled else { throw .cancelled }
    let answer: Response
    do throws(TransportError) { answer = try await http.execute(Self.request(endpoint)) } catch {
      throw CatalogBulkError(error)
    }
    guard !Task.isCancelled else { throw .cancelled }
    let value: Value
    do { value = try Value.decode(answer.body) } catch { throw .decoding(error) }
    if let query = endpoint.manifestQuery, let manifest = value as? BulkManifest {
      do { _ = try query.next(after: manifest) } catch { throw .pagination(error) }
    }
    guard !Task.isCancelled else { throw .cancelled }
    return SourceResponse(
      body: answer.body,
      retrieval: Self.retrieval(
        headers: answer.headers, status: answer.status.code, time: retrievalTime(),
        url: endpoint.url), value: value)
  }

  /// Executes one typed endpoint using its source-specific decoder.
  /// - Parameter endpoint: The operation to execute.
  /// - Returns: One decoded value.
  /// - Throws: `CatalogBulkError` for decoding, transport, or cancellation failures.
  public func send<Value: CatalogBulkResponse>(_ endpoint: Endpoint<Value>)
    async throws(CatalogBulkError) -> Value
  {
    try await response(to: endpoint).value
  }

  /// Executes a reusable request through the endpoint executor.
  /// - Parameter request: The operation to execute.
  /// - Returns: One decoded value.
  /// - Throws: `CatalogBulkError` for decoding, pagination, transport, or cancellation failures.
  public func value<Value: CatalogBulkResponse>(for request: CatalogBulkRequest<Value>)
    async throws(CatalogBulkError) -> Value
  {
    try await send(Self.endpoint(for: request))
  }

  static func endpoint<Value>(for request: CatalogBulkRequest<Value>) -> Endpoint<Value> {
    switch request.resolution {
    case .endpoint(let endpoint): return endpoint
    case .manifest(let query): return Endpoint<Value>(manifestQuery: query)
    }
  }

  static func request<Value>(_ endpoint: Endpoint<Value>) -> Request {
    Request(
      headers: [.acceptEncoding: "identity"],
      options: RequestOptions(redirectPolicy: .never, requiresAuth: false), path: endpoint.path)
  }

  static func retrieval(headers: HTTPFields, status: Int, time: Date, url: URL) -> SourceRetrieval {
    SourceRetrieval(
      headers: headers.map { SourceHeader(name: $0.name.rawName, value: $0.value) },
      retrievedAt: time, status: status, url: url)
  }
}
