#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// Validated partial bytes with their whole-source identity and actual HTTP provenance.
///
/// A partial JSONL range can split a record or UTF-8 sequence. It must not be passed
/// to the complete-shard reader, and this receipt is never a complete-download claim.
public struct BulkRangeReceipt: Hashable, Sendable {
  /// Actual partial bytes saved.
  public let byteCount: Int64
  /// The new file containing only the received interval.
  public let fileURL: URL
  /// Validated received interval, possibly clipped to the known end of the source.
  public let receivedRange: BulkByteRange
  /// Source key, strong validator, total length and optional version pin.
  public let reference: BulkRangeReference
  /// Original interval requested by the caller.
  public let requestedRange: BulkByteRange
  /// Exact response status, headers, requested URL and injected retrieval instant.
  public let retrieval: SourceRetrieval

  /// Creates portable evidence without performing I/O or revalidating a saved file.
  /// - Parameters:
  ///   - byteCount: Saved interval length.
  ///   - fileURL: Completed partial-file destination.
  ///   - receivedRange: Validated response interval.
  ///   - reference: The selected source representation.
  ///   - requestedRange: The caller's interval before EOF clipping.
  ///   - retrieval: Received HTTP evidence.
  public init(
    byteCount: Int64, fileURL: URL, receivedRange: BulkByteRange, reference: BulkRangeReference,
    requestedRange: BulkByteRange, retrieval: SourceRetrieval
  ) {
    self.byteCount = byteCount
    self.fileURL = fileURL
    self.receivedRange = receivedRange
    self.reference = reference
    self.requestedRange = requestedRange
    self.retrieval = retrieval
  }
}
