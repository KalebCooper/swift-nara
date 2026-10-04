import Foundation
import HTTPCore
import HTTPTypes
import SwiftNARADigitalObjectsModels

extension DigitalObjectsClient {
  /// Downloads one explicit interval from a known representation to a new file.
  /// - Parameters:
  ///   - range: One inclusive byte range.
  ///   - reference: Original source, strong validator and known total length.
  ///   - destination: A new local file beneath an existing parent directory.
  /// - Returns: Partial-byte evidence after strict 206 and representation validation.
  /// - Throws: `DigitalObjectsError` for invalid ranges, changed identity, HTTP, bounds or file failure.
  public func downloadRange(
    _ range: DigitalObjectByteRange, of reference: DigitalObjectRangeReference, to destination: URL
  )
    async throws(DigitalObjectsError) -> DigitalObjectRangeReceipt
  {
    try await value(for: .range(range, of: reference), to: destination)
  }

  /// Executes one independent range endpoint without retries or automatic metadata requests.
  /// - Parameters:
  ///   - endpoint: An endpoint made by the range factory.
  ///   - destination: A new file URL; an existing destination is refused before transport.
  /// - Returns: Exact requested and received intervals with source evidence.
  /// - Throws: `DigitalObjectsError`; failure removes only the owned temporary file.
  public func send(_ endpoint: Endpoint<DigitalObjectRangeReceipt>, to destination: URL)
    async throws(DigitalObjectsError) -> DigitalObjectRangeReceipt
  {
    guard !Task.isCancelled else { throw .cancelled }
    guard destination.isFileURL, let range = endpoint.range, let reference = endpoint.rangeReference
    else {
      throw .invalidConfiguration
    }
    let expected: DigitalObjectByteRange
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
      let retrievedAt = retrievalTime()
      try await rejectErrorPage(response)
      if response.status.code == 200 { throw DigitalObjectRangeError.rangeNotHonored }
      guard response.status.code == 206,
        response.headers[.contentEncoding] == nil
          || response.headers[.contentEncoding]?.lowercased() == "identity",
        response.headers[.contentType]?.lowercased().hasPrefix("multipart/") != true
      else { throw DigitalObjectRangeError.invalidResponse }
      let received = try reference.receivedRange(
        contentRange: response.headers[.contentRange], entityTag: response.headers[.eTag],
        requested: range)
      if let text = response.headers[.contentLength] {
        guard !text.isEmpty, text.utf8.allSatisfy({ $0 >= 48 && $0 <= 57 }),
          Int64(text) == received.byteCount
        else {
          throw DigitalObjectRangeError.invalidResponse
        }
      }
      var count: Int64 = 0
      for try await chunk in response.body {
        guard !Task.isCancelled else { throw DigitalObjectsError.cancelled }
        guard Int64(chunk.count) <= received.byteCount - count else {
          throw DigitalObjectRangeError.invalidResponse
        }
        try handle.write(contentsOf: chunk)
        count += Int64(chunk.count)
      }
      guard !Task.isCancelled else { throw DigitalObjectsError.cancelled }
      guard count == received.byteCount else { throw DigitalObjectRangeError.invalidResponse }
      try handle.close()
      try manager.moveItem(at: temporary, to: destination)
      owned = false
      return DigitalObjectRangeReceipt(
        byteCount: count, fileURL: destination,
        headers: response.headers.map { .init(name: $0.name.rawName, value: $0.value) },
        receivedRange: received, reference: reference, requestedRange: range,
        retrievedAt: retrievedAt, status: response.status.code, transportURL: endpoint.url)
    } catch let error as DigitalObjectsError { throw error } catch let error
      as DigitalObjectRangeError
    {
      throw .range(error)
    } catch let error as TransportError {
      if Task.isCancelled { throw .cancelled }
      if case .cancelled = error { throw .cancelled }
      throw .transport(error)
    } catch { throw Task.isCancelled ? .cancelled : .file(error) }
  }

  /// Executes a reusable range request through its independently executable endpoint.
  /// - Parameters:
  ///   - request: A built-in or consumer-defined range operation.
  ///   - destination: New local partial-file destination.
  /// - Returns: Validated partial bytes and retrieval evidence.
  /// - Throws: `DigitalObjectsError` for source, transport, bound or file failure.
  public func value(
    for request: DigitalObjectRequest<DigitalObjectRangeReceipt>, to destination: URL
  )
    async throws(DigitalObjectsError) -> DigitalObjectRangeReceipt
  {
    switch request.resolution {
    case .endpoint(let endpoint): try await send(endpoint, to: destination)
    }
  }
}
