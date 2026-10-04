#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// Validated partial original bytes, distinct from a completed original-file receipt.
///
/// No media decoding or whole-file validity is claimed for an arbitrary byte interval.
public struct DigitalObjectRangeReceipt: Hashable, Sendable {
  /// Actual partial bytes saved.
  public let byteCount: Int64
  /// New file containing only the returned interval.
  public let fileURL: URL
  /// Every received header in received order, including duplicates.
  public let headers: [DigitalObjectReceipt.Header]
  /// Validated returned interval, possibly clipped to the known end of the source.
  public let receivedRange: DigitalObjectByteRange
  /// Original source, strong validator and whole-object length.
  public let reference: DigitalObjectRangeReference
  /// Caller-selected interval before EOF clipping.
  public let requestedRange: DigitalObjectByteRange
  /// Injected response instant, not a publication or modification date.
  public let retrievedAt: Date
  /// Actual response status.
  public let status: Int
  /// Exact requested transport URL.
  public let transportURL: URL

  /// Creates portable evidence without performing I/O or revalidating a saved file.
  /// - Parameters:
  ///   - byteCount: Saved interval length.
  ///   - fileURL: Completed partial-file destination.
  ///   - headers: Received headers in order.
  ///   - receivedRange: Validated response interval.
  ///   - reference: Selected source identity.
  ///   - requestedRange: Caller-selected interval.
  ///   - retrievedAt: Injected receipt instant.
  ///   - status: Received HTTP status.
  ///   - transportURL: Exact requested URL.
  public init(
    byteCount: Int64, fileURL: URL, headers: [DigitalObjectReceipt.Header],
    receivedRange: DigitalObjectByteRange, reference: DigitalObjectRangeReference,
    requestedRange: DigitalObjectByteRange, retrievedAt: Date, status: Int, transportURL: URL
  ) {
    self.byteCount = byteCount
    self.fileURL = fileURL
    self.headers = headers
    self.receivedRange = receivedRange
    self.reference = reference
    self.requestedRange = requestedRange
    self.retrievedAt = retrievedAt
    self.status = status
    self.transportURL = transportURL
  }
}
