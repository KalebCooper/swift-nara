import Foundation
import HTTPCore
import SwiftNARACatalogBulkModels

extension CatalogBulkClient {
  /// Downloads a selected JSONL shard to a new local file only when its condition holds.
  ///
  /// A `200` publishes the complete body to `destination` exactly as
  /// `download(_:to:)` does. A `304 Not Modified` returns its retrieval evidence and creates no
  /// file, so the consumer keeps its previous file and receipt. An unchanged entity tag means no
  /// observed metadata change, not verified byte identity. Nothing is retried, and an existing
  /// file at `destination` is refused before any request is sent.
  /// ```swift
  /// let reference = try ShardReference(key: currentObject.key)
  /// switch try await client.refresh(
  ///   reference, condition: try .ifNoneMatch(previousETag), to: newDestination)
  /// {
  /// case .downloaded(let receipt): print(receipt.byteCount)
  /// case .notModified(let retrieval): print(retrieval.status)
  /// }
  /// ```
  /// - Parameters:
  ///   - shard: The object and optional version to download.
  ///   - condition: The single validator sent with the download.
  ///   - destination: A file URL whose parent exists; an existing file is never replaced.
  /// - Returns: A receipt for a complete new file, or the evidence of a `304` response.
  /// - Throws: `CatalogBulkError.transport` with `TransportError.httpStatus`
  ///   for a `412 Precondition Failed`, which means the object changed and needs renewed
  ///   inventory, and for any other unsuccessful status, keeping its body and headers;
  ///   `CatalogBulkError.cancelled`, `.invalidConfiguration` for a non-file destination,
  ///   `.limitExceeded`, `.sizeMismatch`, or `.file` as `download(_:to:)` throws them.
  public func refresh(_ shard: ShardReference, condition: ShardCondition, to destination: URL)
    async throws(CatalogBulkError) -> ShardRefreshResult
  {
    try await value(for: .refresh(shard, condition: condition), to: destination)
  }

  /// Executes an independently described conditional streaming endpoint.
  ///
  /// The endpoint's condition, when present, is sent as its `If-Match` or `If-None-Match` field
  /// with the exact entity tag text. An endpoint without a condition is sent unconditionally.
  /// A successful body goes to a unique sibling temporary file and moves to `destination` only
  /// when complete. A `304 Not Modified` becomes `ShardRefreshResult.notModified` with the
  /// response's status, headers, source URL, and injected retrieval time; no file or temporary
  /// file remains. Every other unsuccessful status stays a transport failure.
  /// - Parameters:
  ///   - endpoint: The selected conditional shard endpoint.
  ///   - destination: A new local file URL with an existing parent directory.
  /// - Returns: A receipt for a complete new file, or the evidence of a `304` response.
  /// - Throws: `CatalogBulkError.transport` with `TransportError.httpStatus`
  ///   for a `412` or any other unsuccessful status except `304`; `CatalogBulkError.cancelled`,
  ///   `.invalidConfiguration`, `.limitExceeded`, `.sizeMismatch`, or `.file` for the download
  ///   failures `send(_:to:)` for a download endpoint reports.
  public func send(_ endpoint: Endpoint<ShardRefreshResult>, to destination: URL)
    async throws(CatalogBulkError) -> ShardRefreshResult
  {
    do throws(CatalogBulkError) {
      return .downloaded(try await stream(endpoint, to: destination))
    } catch {
      guard case .transport(.httpStatus(body: _, code: 304, let headers)) = error else {
        throw error
      }
      guard !Task.isCancelled else { throw .cancelled }
      return .notModified(
        Self.retrieval(headers: headers, status: 304, time: retrievalTime(), url: endpoint.url))
    }
  }

  /// Executes a reusable conditional shard request through its typed endpoint.
  /// - Parameters:
  ///   - request: The selected conditional shard operation.
  ///   - destination: A new local file URL.
  /// - Returns: A receipt for a complete new file, or the evidence of a `304` response.
  /// - Throws: `CatalogBulkError` as `send(_:to:)` for a refresh endpoint throws it.
  public func value(for request: CatalogBulkRequest<ShardRefreshResult>, to destination: URL)
    async throws(CatalogBulkError) -> ShardRefreshResult
  {
    try await send(Self.endpoint(for: request), to: destination)
  }
}
