import Foundation
import HTTPCore
import HTTPTypes
import SwiftNARADigitalObjectsModels

/// On-demand, bounded downloads of NARA public digital objects.
///
/// Each operation retrieves original media or IIIF content with no redirects, retries, API credentials,
/// or automatic linked requests. Original downloads accept HTML unless the observed
/// CloudFront Error marker is present. That unpublished signal may change or be absent;
/// a receipt proves transfer completion, not authenticity, reuse rights, or OCR accuracy.
/// ```swift
/// let request = DigitalObjectRequest.download(reference)
/// let receipt = try await client.value(for: request, to: destination)
/// print(receipt.byteCount, receipt.mediaType)
/// ```
public struct DigitalObjectsClient: Sendable {
  let configuration: DigitalObjectsConfiguration
  let http: HTTPClient
  let retrievalTime: @Sendable () -> Date

  /// Creates a client with an explicit transport and receipt clock.
  /// - Parameters:
  ///   - configuration: Caller identity and byte budgets.
  ///   - retrievalTime: Injected receipt instants, sampled after response headers arrive.
  ///   - transport: A transport honoring redirect refusal and streaming body cancellation.
  public init(
    configuration: DigitalObjectsConfiguration, retrievalTime: @escaping @Sendable () -> Date,
    transport: any Transport
  ) {
    self.configuration = configuration
    self.retrievalTime = retrievalTime
    guard let origin = URL(string: Endpoint<DigitalObjectReceipt>.origin) else {
      preconditionFailure("The fixed HTTPS media origin is valid.")
    }
    http = HTTPClient(
      baseURL: origin, defaultHeaders: [.userAgent: configuration.userAgent],
      redirectPolicy: .never,
      transport: ErrorBodyTransport(
        base: transport, maximumBytes: configuration.maximumErrorBodyBytes))
  }

  /// Downloads one original digital object to a new file.
  /// - Parameters:
  ///   - reference: The validated source identity and public transport mapping.
  ///   - destination: A new file URL whose parent directory exists.
  /// - Returns: A receipt after complete bounded bytes have been published.
  /// - Throws: `DigitalObjectsError` for cancellation, source, bounds, or file failures.
  public func download(_ reference: DigitalObjectReference, to destination: URL)
    async throws(DigitalObjectsError) -> DigitalObjectReceipt
  {
    try await value(for: .download(reference), to: destination)
  }

  /// Refuses the observed substituted-page marker, retaining only bounded diagnostic bytes.
  func rejectErrorPage(_ response: StreamedResponse) async throws(DigitalObjectsError) {
    do {
      if response.headers.contains(where: {
        $0.name.rawName.lowercased() == "x-cache"
          && $0.value.trimmingCharacters(in: .whitespaces).lowercased() == "error from cloudfront"
      }) {
        var bytes = Data()
        var truncated = false
        for try await chunk in response.body {
          guard !Task.isCancelled else { throw DigitalObjectsError.cancelled }
          let remaining = configuration.maximumErrorBodyBytes - bytes.count
          bytes.append(chunk.prefix(remaining))
          if chunk.count > remaining {
            truncated = true
            break
          }
        }
        throw DigitalObjectsError.errorPage(
          body: bytes, code: response.status.code, headers: response.headers, isTruncated: truncated
        )
      }
    } catch let error as DigitalObjectsError {
      throw error
    } catch {
      if Task.isCancelled { throw .cancelled }
      if let failure = error as? TransportError { throw .transport(failure) }
      throw .transport(.transport(kind: .other, underlying: error))
    }
  }

  /// Executes a download endpoint, preserving identity when its factory supplied one.
  /// - Parameters:
  ///   - endpoint: A reference-based or independently validated public media endpoint.
  ///   - destination: A new local file URL; existing destinations are refused before I/O.
  /// - Returns: Original reference, headers, response time, URL, and saved-byte evidence.
  /// - Throws: `DigitalObjectsError`; failure removes only the owned sibling temporary.
  public func send(_ endpoint: Endpoint<DigitalObjectReceipt>, to destination: URL)
    async throws(DigitalObjectsError) -> DigitalObjectReceipt
  {
    let result = try await transfer(path: endpoint.path, to: destination, validatesJPEG: false)
    return DigitalObjectReceipt(
      byteCount: result.byteCount, fileURL: result.fileURL, headers: result.headers,
      reference: endpoint.reference, retrievedAt: result.retrievedAt, status: result.status,
      transportURL: endpoint.url)
  }

  /// Streams one validated path, publishing only complete original or JPEG bytes.
  func transfer(path: String, to destination: URL, validatesJPEG: Bool)
    async throws(DigitalObjectsError) -> FileTransfer
  {
    guard !Task.isCancelled else { throw .cancelled }
    guard destination.isFileURL else { throw .invalidConfiguration }
    let manager = FileManager.default
    let temporary = destination.deletingLastPathComponent().appendingPathComponent(
      ".nara-media-" + UUID().uuidString + ".partial")
    var ownedTemporary = false
    defer { if ownedTemporary { try? manager.removeItem(at: temporary) } }
    do {
      // attributesOfItem also sees a dangling symbolic link, which fileExists alone misses.
      guard (try? manager.attributesOfItem(atPath: destination.path)) == nil else {
        throw CocoaError(.fileWriteFileExists)
      }
      try Data().write(to: temporary, options: .withoutOverwriting)
      ownedTemporary = true
      let handle = try FileHandle(forWritingTo: temporary)
      defer { try? handle.close() }
      let response = try await http.streamResponse(
        Request(
          headers: validatesJPEG
            ? [.accept: "image/jpeg", .acceptEncoding: "identity"]
            : [.acceptEncoding: "identity"],
          options: RequestOptions(redirectPolicy: .never, requiresAuth: false), path: path)
      )
      let retrievedAt = retrievalTime()
      try await rejectErrorPage(response)
      guard response.status.code == 200, response.headers[.contentRange] == nil,
        response.headers[.contentEncoding] == nil
          || response.headers[.contentEncoding]?.lowercased() == "identity"
      else { throw DigitalObjectsError.sizeMismatch }
      if validatesJPEG, let type = response.headers[.contentType] {
        guard
          type.split(separator: ";").first?.trimmingCharacters(in: .whitespaces).lowercased()
            == "image/jpeg"
        else { throw DigitalObjectsError.invalidImage }
      }
      let declaredLength: Int64?
      if let text = response.headers[.contentLength] {
        guard !text.isEmpty, text.utf8.allSatisfy({ $0 >= 48 && $0 <= 57 }),
          let length = Int64(text)
        else { throw DigitalObjectsError.sizeMismatch }
        declaredLength = length
      } else {
        declaredLength = nil
      }
      if let declaredLength, declaredLength > configuration.maximumObjectBytes {
        throw DigitalObjectsError.limitExceeded
      }
      var count: Int64 = 0
      var signature = Data()
      for try await chunk in response.body {
        guard !Task.isCancelled else { throw DigitalObjectsError.cancelled }
        guard Int64(chunk.count) <= configuration.maximumObjectBytes - count else {
          throw DigitalObjectsError.limitExceeded
        }
        if let declaredLength, Int64(chunk.count) > declaredLength - count {
          throw DigitalObjectsError.sizeMismatch
        }
        if validatesJPEG && signature.count < 3 {
          signature.append(chunk.prefix(3 - signature.count))
          if signature.count == 3 && signature != Data([0xFF, 0xD8, 0xFF]) {
            throw DigitalObjectsError.invalidImage
          }
        }
        try handle.write(contentsOf: chunk)
        count += Int64(chunk.count)
      }
      guard !Task.isCancelled else { throw DigitalObjectsError.cancelled }
      guard declaredLength == nil || declaredLength == count else {
        throw DigitalObjectsError.sizeMismatch
      }
      guard !validatesJPEG || signature == Data([0xFF, 0xD8, 0xFF]) else {
        throw DigitalObjectsError.invalidImage
      }
      try handle.close()
      try manager.moveItem(at: temporary, to: destination)
      ownedTemporary = false
      return FileTransfer(
        byteCount: count, fileURL: destination,
        headers: response.headers.map { .init(name: $0.name.rawName, value: $0.value) },
        retrievedAt: retrievedAt, status: response.status.code)
    } catch let error as DigitalObjectsError {
      throw error
    } catch let error as TransportError {
      if Task.isCancelled { throw .cancelled }
      if case .cancelled = error { throw .cancelled }
      throw .transport(error)
    } catch { throw Task.isCancelled ? .cancelled : .file(error) }
  }

  /// Executes a reusable request through the same endpoint executor.
  /// - Parameters:
  ///   - request: A built-in or consumer-defined download request.
  ///   - destination: A new local file URL.
  /// - Returns: A completed original-file receipt.
  /// - Throws: `DigitalObjectsError` for retrieval or local file failures.
  public func value(for request: DigitalObjectRequest<DigitalObjectReceipt>, to destination: URL)
    async throws(DigitalObjectsError) -> DigitalObjectReceipt
  {
    switch request.resolution {
    case .endpoint(let endpoint): try await send(endpoint, to: destination)
    }
  }

  struct FileTransfer {
    let byteCount: Int64
    let fileURL: URL
    let headers: [DigitalObjectReceipt.Header]
    let retrievedAt: Date
    let status: Int
  }
}
