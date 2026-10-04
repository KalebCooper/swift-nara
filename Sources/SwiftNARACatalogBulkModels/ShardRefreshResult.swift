#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// The outcome of a conditional shard download.
///
/// A new body produces a receipt for a complete new file. A not-modified response produces only
/// its retrieval evidence: no file, byte count, or receipt exists for it, and the consumer keeps
/// its previous file and receipt.
/// ```swift
/// switch result {
/// case .downloaded(let receipt): print(receipt.byteCount, receipt.retrieval.status)
/// case .notModified(let retrieval): print(retrieval.status)
/// }
/// ```
public enum ShardRefreshResult: Codable, Hashable, Sendable {
  /// The source returned a body, saved completely to a new file.
  case downloaded(ShardReceipt)
  /// The source reported no change for the condition; nothing was saved.
  case notModified(SourceRetrieval)
}
