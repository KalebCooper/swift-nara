import Foundation
import SwiftNARADigitalObjectsModels

extension DigitalObjectsClient {
  /// Downloads one validated JPEG derivative, with no implicit information or original fetch.
  /// - Parameters:
  ///   - request: A transform validated against previously obtained information.
  ///   - destination: A new destination beneath an existing local directory.
  /// - Returns: Separate derivative evidence after complete bounded transfer.
  /// - Throws: `DigitalObjectsError` for cancellation, response, byte or file failures.
  public func downloadImage(_ request: IIIFImageRequest, to destination: URL)
    async throws(DigitalObjectsError) -> IIIFImageReceipt
  {
    try await value(for: .image(request), to: destination)
  }

  /// Executes an independent derivative endpoint.
  /// - Parameters:
  ///   - endpoint: An image endpoint created from a validated request.
  ///   - destination: A new local file URL.
  /// - Returns: Original identity, requested transform and actual derivative evidence.
  /// - Throws: `DigitalObjectsError`; failed downloads remove their owned temporary file.
  public func send(_ endpoint: Endpoint<IIIFImageReceipt>, to destination: URL)
    async throws(DigitalObjectsError) -> IIIFImageReceipt
  {
    guard !Task.isCancelled else { throw .cancelled }
    guard let request = endpoint.imageRequest else { throw .invalidConfiguration }
    let result = try await transfer(path: endpoint.path, to: destination, validatesJPEG: true)
    return IIIFImageReceipt(
      byteCount: result.byteCount, fileURL: result.fileURL, headers: result.headers,
      request: request, retrievedAt: result.retrievedAt, status: result.status,
      transportURL: endpoint.url)
  }

  /// Executes a reusable derivative request through the same file-transfer executor.
  /// - Parameters:
  ///   - request: A built-in or consumer-defined image request.
  ///   - destination: A new local file URL.
  /// - Returns: Completed derivative evidence.
  /// - Throws: `DigitalObjectsError` for invalid operation, retrieval or publication failure.
  public func value(for request: DigitalObjectRequest<IIIFImageReceipt>, to destination: URL)
    async throws(DigitalObjectsError) -> IIIFImageReceipt
  {
    switch request.resolution {
    case .endpoint(let endpoint): try await send(endpoint, to: destination)
    }
  }
}
