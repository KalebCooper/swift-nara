/// Explicit transfer and logical disk budgets for one selected archive.
///
/// No large-archive default is assumed. Disk limits count owned file contents, not filesystem
/// allocation blocks or metadata, and do not reserve free capacity. Local I/O can still fail.
public struct BulkArchiveDownloadLimits: Hashable, Sendable {
  /// Maximum complete archive length.
  public let maximumByteCount: Int64
  /// Maximum owned file-content bytes, including resume fragments and sidecars.
  public let maximumWorkspaceBytes: Int64

  /// Creates explicit positive budgets without inspecting a disk.
  /// - Parameters:
  ///   - maximumByteCount: Maximum bytes in the completed archive.
  ///   - maximumWorkspaceBytes: Maximum logical bytes in owned working files.
  /// - Throws: `CatalogBulkError.invalidConfiguration` for a nonpositive bound.
  public init(maximumByteCount: Int64, maximumWorkspaceBytes: Int64) throws(CatalogBulkError) {
    guard maximumByteCount > 0, maximumWorkspaceBytes > 0 else { throw .invalidConfiguration }
    self.maximumByteCount = maximumByteCount
    self.maximumWorkspaceBytes = maximumWorkspaceBytes
  }

  func validateResume(rangeBytes: Int64, totalByteCount: Int64) throws(CatalogBulkError) {
    guard totalByteCount <= maximumByteCount, totalByteCount <= maximumWorkspaceBytes else {
      throw .limitExceeded
    }
    let remaining = maximumWorkspaceBytes - totalByteCount
    let fragment = min(rangeBytes, totalByteCount)
    // Atomic sidecar replacement can temporarily retain both bounded one-MiB versions.
    guard fragment <= remaining, 2 * 1_048_576 <= remaining - fragment else {
      throw .limitExceeded
    }
  }
}
