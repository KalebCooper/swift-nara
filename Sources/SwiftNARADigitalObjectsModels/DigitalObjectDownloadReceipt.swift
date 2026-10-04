#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// Complete validated bytes published from a durable original-download checkpoint.
///
/// The destination is a new hard link on the same filesystem. The owned partial and
/// sidecar remain until explicit discard; discard removes neither this destination nor
/// unrelated files. Do not modify the partial, sidecar, or destination during an operation.
public struct DigitalObjectDownloadReceipt: Hashable, Sendable {
  /// The complete durable checkpoint, including source identity, digest and last-range evidence.
  public let checkpoint: DigitalObjectDownloadCheckpoint
  /// The newly published complete file.
  public let fileURL: URL

  /// The verified whole-representation byte count.
  public var byteCount: Int64 { checkpoint.committedByteCount }

  package init(checkpoint: DigitalObjectDownloadCheckpoint, fileURL: URL) {
    self.checkpoint = checkpoint
    self.fileURL = fileURL
  }
}
