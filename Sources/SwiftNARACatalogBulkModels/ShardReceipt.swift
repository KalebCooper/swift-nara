#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// A successfully completed local shard download.
///
/// No receipt is returned for a partial download. Header ETags are version hints, not content
/// digests. Consumers may hash the saved bytes with their chosen storage implementation.
public struct ShardReceipt: Codable, Hashable, Sendable {
  /// The number of source bytes saved.
  public let byteCount: Int64
  /// The destination containing the complete original bytes.
  public let fileURL: URL
  /// The exact source URL, retrieval time, status, and headers.
  public let retrieval: SourceRetrieval
  /// Creates a receipt for a supplied local file and its known retrieval evidence.
  public init(byteCount: Int64, fileURL: URL, retrieval: SourceRetrieval) {
    self.byteCount = byteCount; self.fileURL = fileURL; self.retrieval = retrieval
  }
}
