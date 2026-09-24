#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// One JSONL line with its retrieval and byte-location evidence.
public struct CatalogLine: Sendable {
  /// Zero-based byte offset in the downloaded file.
  public let byteOffset: Int64
  /// One-based physical line number, including lines before an error.
  public let lineNumber: Int64
  /// Exact bytes, including LF or CRLF when present.
  public let rawBytes: Data
  /// The decoded archival record.
  public let record: CatalogRecord
  /// The complete download receipt, retained for every line.
  public let shard: ShardReceipt
  /// Creates a decoded line with its source evidence.
  public init(
    byteOffset: Int64, lineNumber: Int64, rawBytes: Data, record: CatalogRecord, shard: ShardReceipt
  ) {
    self.byteOffset = byteOffset; self.lineNumber = lineNumber; self.rawBytes = rawBytes
    self.record = record; self.shard = shard
  }
}
