#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// Completed derivative-file evidence, distinct from an original digital-object receipt.
///
/// A JPEG signature check is not complete image decoding or proof of authenticity,
/// requested dimensions, or reuse rights. Preserve the associated source restrictions.
public struct IIIFImageReceipt: Hashable, Sendable {
  /// Number of derivative bytes saved.
  public let byteCount: Int64
  /// The new local destination containing the complete transfer.
  public let fileURL: URL
  /// Received response headers in source order.
  public let headers: [DigitalObjectReceipt.Header]
  /// The validated information and exact requested transform.
  public let request: IIIFImageRequest
  /// Injected retrieval instant sampled after response headers arrived.
  public let retrievedAt: Date
  /// Actual HTTP status.
  public let status: Int
  /// Actual fixed-origin requested URL, without redirects.
  public let transportURL: URL

  /// Information identity used in this request.
  public var informationID: String { request.information.id }
  /// The declared media type, or nil when the response did not supply it.
  public var mediaType: String? {
    headers.first { $0.name.lowercased() == "content-type" }?.value
  }
  /// The original source identity; these saved bytes are a derivative of that source.
  public var reference: DigitalObjectReference { request.information.reference.reference }

  /// Creates portable derivative evidence without I/O or revalidating downloaded bytes.
  /// - Parameters:
  ///   - byteCount: Saved derivative byte count.
  ///   - fileURL: Completed file destination.
  ///   - headers: Received headers in source order.
  ///   - request: Validated transform and information evidence.
  ///   - retrievedAt: Caller-supplied retrieval instant.
  ///   - status: Received HTTP status.
  ///   - transportURL: Requested derivative URL.
  public init(
    byteCount: Int64, fileURL: URL, headers: [DigitalObjectReceipt.Header],
    request: IIIFImageRequest, retrievedAt: Date, status: Int, transportURL: URL
  ) {
    self.byteCount = byteCount
    self.fileURL = fileURL
    self.headers = headers
    self.request = request
    self.retrievedAt = retrievedAt
    self.status = status
    self.transportURL = transportURL
  }
}
