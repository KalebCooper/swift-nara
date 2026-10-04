import Foundation
import HTTPCore
import HTTPTypes
import SwiftNARACatalogBulkModels

extension CatalogBulkClient {
  /// Downloads one explicit interval from a known representation to a new file.
  /// - Parameters:
  ///   - range: One inclusive byte range.
  ///   - reference: Strong validator, known total length, key and optional version.
  ///   - destination: A new local file beneath an existing parent directory.
  /// - Returns: Partial-byte evidence after strict 206 and representation validation.
  /// - Throws: `CatalogBulkError` for invalid ranges, changed identity, HTTP, bounds or file failure.
  public func downloadRange(
    _ range: BulkByteRange, of reference: BulkRangeReference, to destination: URL
  )
    async throws(CatalogBulkError) -> BulkRangeReceipt
  {
    try await value(for: .range(range, of: reference), to: destination)
  }

  /// Executes one independent range endpoint without retries or automatic metadata requests.
  /// - Parameters:
  ///   - endpoint: An endpoint made by the range factory.
  ///   - destination: A new file URL; an existing destination is refused before transport.
  /// - Returns: Exact requested and received intervals with source evidence.
  /// - Throws: `CatalogBulkError`; failure removes only the owned temporary file.
  public func send(_ endpoint: Endpoint<BulkRangeReceipt>, to destination: URL)
    async throws(CatalogBulkError) -> BulkRangeReceipt
  {
    guard !Task.isCancelled else { throw .cancelled }
    guard destination.isFileURL, let range = endpoint.range, let reference = endpoint.rangeReference
    else {
      throw .invalidConfiguration
    }
    let expected: BulkByteRange
    do { expected = try range.clipped(to: reference.totalByteCount) } catch { throw .range(error) }
    guard expected.byteCount <= configuration.maximumRangeBytes else { throw .limitExceeded }
    let manager = FileManager.default
    let temporary = destination.deletingLastPathComponent().appendingPathComponent(
      ".nara-range-" + UUID().uuidString + ".partial")
    var owned = false
    defer { if owned { try? manager.removeItem(at: temporary) } }
    do {
      guard (try? manager.attributesOfItem(atPath: destination.path)) == nil else {
        throw CocoaError(.fileWriteFileExists)
      }
      try Data().write(to: temporary, options: .withoutOverwriting)
      owned = true
      let handle = try FileHandle(forWritingTo: temporary)
      defer { try? handle.close() }
      let response = try await http.streamResponse(
        Request(
          headers: [
            .acceptEncoding: "identity", .ifMatch: reference.entityTag, .range: range.headerValue,
          ],
          options: RequestOptions(redirectPolicy: .never, requiresAuth: false), path: endpoint.path)
      )
      let retrieval = Self.retrieval(
        headers: response.headers, status: response.status.code, time: retrievalTime(),
        url: endpoint.url)
      if response.status.code == 200 { throw BulkRangeError.rangeNotHonored }
      guard response.status.code == 206,
        response.headers[.contentEncoding] == nil
          || response.headers[.contentEncoding]?.lowercased() == "identity",
        response.headers[.contentType]?.lowercased().hasPrefix("multipart/") != true
      else { throw BulkRangeError.invalidResponse }
      let versionName = HTTPField.Name("x-amz-version-id")
      let received = try reference.receivedRange(
        contentRange: response.headers[.contentRange], entityTag: response.headers[.eTag],
        requested: range,
        versionID: versionName.flatMap { response.headers[$0] })
      if let text = response.headers[.contentLength] {
        guard !text.isEmpty, text.utf8.allSatisfy({ $0 >= 48 && $0 <= 57 }),
          Int64(text) == received.byteCount
        else {
          throw BulkRangeError.invalidResponse
        }
      }
      var count: Int64 = 0
      for try await chunk in response.body {
        guard !Task.isCancelled else { throw CatalogBulkError.cancelled }
        guard Int64(chunk.count) <= received.byteCount - count else {
          throw BulkRangeError.invalidResponse
        }
        try handle.write(contentsOf: chunk)
        count += Int64(chunk.count)
      }
      guard !Task.isCancelled else { throw CatalogBulkError.cancelled }
      guard count == received.byteCount else { throw BulkRangeError.invalidResponse }
      try handle.close()
      try manager.moveItem(at: temporary, to: destination)
      owned = false
      return BulkRangeReceipt(
        byteCount: count, fileURL: destination, receivedRange: received,
        reference: reference, requestedRange: range, retrieval: retrieval)
    } catch let error as CatalogBulkError { throw error } catch let error as BulkRangeError {
      throw .range(error)
    } catch let error as TransportError {
      throw Task.isCancelled ? .cancelled : CatalogBulkError(error)
    } catch { throw Task.isCancelled ? .cancelled : .file(error) }
  }

  /// Executes a reusable range request through its independently executable endpoint.
  /// - Parameters:
  ///   - request: A built-in or consumer-defined range operation.
  ///   - destination: New local partial-file destination.
  /// - Returns: Validated partial bytes and retrieval evidence.
  /// - Throws: `CatalogBulkError` for source, transport, bound or file failure.
  public func value(for request: CatalogBulkRequest<BulkRangeReceipt>, to destination: URL)
    async throws(CatalogBulkError) -> BulkRangeReceipt
  {
    try await send(Self.endpoint(for: request), to: destination)
  }
}
