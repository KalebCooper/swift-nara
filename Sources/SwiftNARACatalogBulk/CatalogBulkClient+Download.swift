import Foundation
import HTTPCore
import SwiftNARACatalogBulkModels

extension CatalogBulkClient {
  /// Streams a selected JSONL shard to a new local file.
  /// - Parameters:
  ///   - shard: The object and optional version to download.
  ///   - destination: A file URL whose parent exists; an existing file is never replaced.
  /// - Returns: A receipt only after the complete source body has been saved.
  /// - Throws: `CatalogBulkError` for cancellation, bounds, incomplete bytes, HTTP, or file failures.
  public func download(_ shard: ShardReference, to destination: URL) async throws(CatalogBulkError)
    -> ShardReceipt
  {
    try await value(for: .shard(shard), to: destination)
  }

  /// Executes an independently described streaming endpoint.
  ///
  /// Bytes go to a unique sibling temporary file, then move to the requested destination after
  /// successful completion. Failure removes only that temporary file. No partial receipt is returned.
  /// - Parameters:
  ///   - endpoint: The selected shard endpoint.
  ///   - destination: A new local file URL with an existing parent directory.
  /// - Returns: The exact streamed status, headers, source URL, retrieval time, and saved byte count.
  /// - Throws: `CatalogBulkError` for cancellation, size mismatches, HTTP, or local file failures.
  public func send(_ endpoint: Endpoint<ShardReceipt>, to destination: URL)
    async throws(CatalogBulkError) -> ShardReceipt
  {
    guard !Task.isCancelled else { throw .cancelled }
    guard destination.isFileURL else { throw .invalidConfiguration }
    let manager = FileManager.default
    let temporary = destination.deletingLastPathComponent().appendingPathComponent(
      ".nara-" + UUID().uuidString + ".partial")
    var ownedTemporary = false
    defer { if ownedTemporary { try? manager.removeItem(at: temporary) } }
    do {
      guard !manager.fileExists(atPath: destination.path) else {
        throw CocoaError(.fileWriteFileExists)
      }
      guard manager.createFile(atPath: temporary.path, contents: nil) else {
        throw CocoaError(.fileWriteUnknown)
      }
      ownedTemporary = true
      let handle = try FileHandle(forWritingTo: temporary)
      defer { try? handle.close() }
      let response = try await http.streamResponse(Self.request(endpoint))
      guard response.status.code == 200, response.headers[.contentRange] == nil else {
        throw CatalogBulkError.sizeMismatch
      }
      let retrieval = Self.retrieval(
        headers: response.headers, status: response.status.code, time: retrievalTime(),
        url: endpoint.url)
      let declaredLength: Int64?
      if let text = response.headers[.contentLength] {
        guard let length = Int64(text), length >= 0 else { throw CatalogBulkError.sizeMismatch }
        declaredLength = length
      } else {
        declaredLength = nil
      }
      if let declaredLength, declaredLength > configuration.maximumShardBytes {
        throw CatalogBulkError.limitExceeded
      }
      var count: Int64 = 0
      for try await chunk in response.body {
        guard !Task.isCancelled else { throw CatalogBulkError.cancelled }
        guard Int64(chunk.count) <= configuration.maximumShardBytes - count else {
          throw CatalogBulkError.limitExceeded
        }
        try handle.write(contentsOf: chunk)
        count += Int64(chunk.count)
      }
      guard !Task.isCancelled else { throw CatalogBulkError.cancelled }
      // A Content-Encoding may describe compressed wire bytes; reject it rather than invent byte identity.
      guard
        response.headers[.contentEncoding] == nil
          || response.headers[.contentEncoding] == "identity"
      else { throw CatalogBulkError.sizeMismatch }
      guard declaredLength == nil || declaredLength == count else {
        throw CatalogBulkError.sizeMismatch
      }
      try handle.close()
      try manager.moveItem(at: temporary, to: destination)
      ownedTemporary = false
      return ShardReceipt(byteCount: count, fileURL: destination, retrieval: retrieval)
    } catch let error as CatalogBulkError { throw error } catch let error as TransportError {
      throw CatalogBulkError(error)
    } catch { throw Task.isCancelled ? .cancelled : .file(error) }
  }

  /// Downloads a reusable shard request through its typed endpoint.
  /// - Parameters:
  ///   - request: The selected shard operation.
  ///   - destination: A new local file URL.
  /// - Returns: A completed download receipt; local iteration is a separate operation.
  /// - Throws: `CatalogBulkError` for download or file failures.
  public func value(for request: CatalogBulkRequest<ShardReceipt>, to destination: URL)
    async throws(CatalogBulkError) -> ShardReceipt
  {
    try await send(Self.endpoint(for: request), to: destination)
  }
}
