import SwiftNARACatalogBulkModels

/// A resume failure and the last checkpoint verified and synchronized by this operation.
public struct BulkDownloadFailure: Error {
  /// The last known durable checkpoint, or nil when local verification did not finish.
  ///
  /// The sidecar may contain later consistent progress if saving completed just before an
  /// interruption. The next explicit resume reloads and validates that sidecar.
  public let checkpoint: BulkDownloadCheckpoint?
  /// The source, local-state, cancellation or file failure. No automatic retry is performed.
  public let reason: CatalogBulkError

  init(checkpoint: BulkDownloadCheckpoint?, reason: CatalogBulkError) {
    self.checkpoint = checkpoint
    self.reason = reason
  }
}
