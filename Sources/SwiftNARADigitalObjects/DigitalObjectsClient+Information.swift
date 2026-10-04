import Foundation
import HTTPCore
import HTTPTypes
import SwiftNARADigitalObjectsModels

extension DigitalObjectsClient {
  /// Retrieves one bounded image-information document without fetching linked content.
  /// - Parameter reference: The expected service and original source.
  /// - Returns: Validated information, raw bytes, headers and retrieval time.
  /// - Throws: `DigitalObjectsError` for invalid information, HTTP, bounds or cancellation.
  public func imageInformation(for reference: IIIFImageReference)
    async throws(DigitalObjectsError) -> IIIFImageInformation
  {
    try await value(for: .imageInformation(reference))
  }

  /// Executes an independent information endpoint.
  /// - Parameter endpoint: An information endpoint created for a validated IIIF reference.
  /// - Returns: The bounded document with exact source and HTTP evidence.
  /// - Throws: `DigitalObjectsError` for invalid endpoint kind, response or transport failures.
  public func send(_ endpoint: Endpoint<IIIFImageInformation>)
    async throws(DigitalObjectsError) -> IIIFImageInformation
  {
    guard !Task.isCancelled else { throw .cancelled }
    guard let reference = endpoint.imageReference else { throw .invalidConfiguration }
    do {
      let response = try await http.streamResponse(
        Request(
          headers: [.accept: "application/ld+json, application/json", .acceptEncoding: "identity"],
          options: RequestOptions(redirectPolicy: .never, requiresAuth: false), path: endpoint.path)
      )
      let time = retrievalTime()
      try await rejectErrorPage(response)
      guard response.status.code == 200, response.headers[.contentRange] == nil,
        response.headers[.contentEncoding] == nil
          || response.headers[.contentEncoding]?.lowercased() == "identity"
      else { throw DigitalObjectsError.sizeMismatch }
      if let contentType = response.headers[.contentType] {
        let mediaType = contentType.split(separator: ";").first?.trimmingCharacters(
          in: .whitespaces
        ).lowercased()
        guard mediaType == "application/json" || mediaType == "application/ld+json" else {
          throw DigitalObjectsError.information(.malformedInformation)
        }
      }
      let length: Int?
      if let value = response.headers[.contentLength] {
        guard !value.isEmpty, value.utf8.allSatisfy({ $0 >= 48 && $0 <= 57 }),
          let count = Int(value)
        else { throw DigitalObjectsError.sizeMismatch }
        guard count <= configuration.maximumInformationBytes else {
          throw DigitalObjectsError.limitExceeded
        }
        length = count
      } else {
        length = nil
      }
      var bytes = Data()
      for try await chunk in response.body {
        guard !Task.isCancelled else { throw DigitalObjectsError.cancelled }
        guard chunk.count <= configuration.maximumInformationBytes - bytes.count else {
          throw DigitalObjectsError.limitExceeded
        }
        bytes.append(chunk)
      }
      guard !Task.isCancelled else { throw DigitalObjectsError.cancelled }
      guard length == nil || length == bytes.count else { throw DigitalObjectsError.sizeMismatch }
      return try IIIFImageInformation.decode(
        bytes, headers: response.headers.map { .init(name: $0.name.rawName, value: $0.value) },
        maximumBytes: configuration.maximumInformationBytes, reference: reference,
        retrievedAt: time, status: response.status.code)
    } catch let error as DigitalObjectsError {
      throw error
    } catch let error as IIIFImageError {
      throw .information(error)
    } catch {
      if Task.isCancelled { throw .cancelled }
      if let error = error as? TransportError {
        if case .cancelled = error { throw .cancelled }
        throw .transport(error)
      }
      throw .information(.malformedInformation)
    }
  }

  /// Executes a reusable image-information request through its endpoint.
  /// - Parameter request: A built-in or consumer-defined information request.
  /// - Returns: Validated information and retrieval evidence.
  /// - Throws: `DigitalObjectsError` for source, bounds, or transport failures.
  public func value(for request: DigitalObjectRequest<IIIFImageInformation>)
    async throws(DigitalObjectsError) -> IIIFImageInformation
  {
    switch request.resolution {
    case .endpoint(let endpoint): try await send(endpoint)
    }
  }
}
