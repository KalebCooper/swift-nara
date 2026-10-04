#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// A versioned, caller-retained description of durable original bytes.
///
/// Decoding validates values but performs no I/O or file-ownership verification.
/// A checkpoint is integrity evidence for accidental
/// corruption, not authentication against a party able to rewrite both file and sidecar.
/// The caller must keep the workspace private and retain it until completion or explicit discard.
public struct BulkDownloadCheckpoint: Codable, Hashable, Sendable {
  /// The durable prefix length; bytes beyond this offset are uncommitted.
  public let committedByteCount: Int64
  /// The persisted encoding contract, always identity.
  public let contentEncoding: String
  /// The filesystem device containing the SDK-created partial file.
  public let deviceID: UInt64
  /// The checkpoint schema version, currently one.
  public let formatVersion: Int
  /// The unique download identifier and owned workspace-directory suffix.
  public let id: UUID
  /// The identity of the SDK-created regular partial file.
  public let inode: UInt64
  /// Headers from the last committed 206 response; empty before the first range.
  public let lastResponseHeaders: [SourceHeader]
  /// The injected retrieval time of the last committed range, or nil before transfer.
  public let lastRetrievedAt: Date?
  /// The SDK-owned partial file. Its parent also contains checkpoint.json.
  public let partialFileURL: URL
  /// Lowercase SHA-256 of exactly the committed prefix, independent of the ETag.
  public let prefixSHA256: String
  /// The exact source representation selected for this download.
  public let reference: BulkRangeReference

  /// The sidecar updated after file bytes have been synchronized.
  public var checkpointURL: URL {
    partialFileURL.deletingLastPathComponent().appendingPathComponent("checkpoint.json")
  }

  /// The exact fixed-origin URL for the selected representation.
  public var transportURL: URL { reference.url }

  /// Decodes a checkpoint, rejecting unsupported formats and inconsistent bounds or paths.
  /// - Parameter decoder: The previously persisted checkpoint.
  /// - Throws: A decoding error or `BulkDownloadStateError.invalidCheckpoint`.
  public init(from decoder: any Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    guard try c.decode(Int.self, forKey: .formatVersion) == 1,
      try c.decode(String.self, forKey: .contentEncoding) == "identity"
    else { throw BulkDownloadStateError.invalidCheckpoint }
    try self.init(
      committedByteCount: try c.decode(Int64.self, forKey: .committedByteCount),
      deviceID: try c.decode(UInt64.self, forKey: .deviceID),
      id: try c.decode(UUID.self, forKey: .id),
      inode: try c.decode(UInt64.self, forKey: .inode),
      lastResponseHeaders: try c.decode([SourceHeader].self, forKey: .lastResponseHeaders),
      lastRetrievedAt: try c.decodeIfPresent(Date.self, forKey: .lastRetrievedAt),
      partialFileURL: try c.decode(URL.self, forKey: .partialFileURL),
      prefixSHA256: try c.decode(String.self, forKey: .prefixSHA256),
      reference: try c.decode(BulkRangeReference.self, forKey: .reference))
  }

  package init(
    committedByteCount: Int64,
    deviceID: UInt64,
    id: UUID,
    inode: UInt64,
    lastResponseHeaders: [SourceHeader],
    lastRetrievedAt: Date?,
    partialFileURL: URL,
    prefixSHA256: String,
    reference: BulkRangeReference
  ) throws(BulkDownloadStateError) {
    guard committedByteCount >= 0, committedByteCount <= reference.totalByteCount,
      partialFileURL.isFileURL, partialFileURL.query == nil, partialFileURL.fragment == nil,
      partialFileURL.host == nil || partialFileURL.host == "",
      partialFileURL.user == nil, partialFileURL.password == nil, partialFileURL.port == nil,
      partialFileURL.standardizedFileURL == partialFileURL,
      partialFileURL.lastPathComponent == "partial",
      partialFileURL.deletingLastPathComponent().lastPathComponent == ".nara-download-"
        + id.uuidString,
      prefixSHA256.utf8.count == 64,
      prefixSHA256.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }),
      (committedByteCount == 0 && lastRetrievedAt == nil && lastResponseHeaders.isEmpty
        && prefixSHA256 == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
        || (committedByteCount > 0 && lastRetrievedAt != nil)
    else { throw .invalidCheckpoint }
    self.committedByteCount = committedByteCount
    self.contentEncoding = "identity"
    self.deviceID = deviceID
    self.formatVersion = 1
    self.id = id
    self.inode = inode
    self.lastResponseHeaders = lastResponseHeaders
    self.lastRetrievedAt = lastRetrievedAt
    self.partialFileURL = partialFileURL
    self.prefixSHA256 = prefixSHA256
    self.reference = reference
  }

  private enum CodingKeys: String, CodingKey {
    case committedByteCount
    case contentEncoding
    case deviceID
    case formatVersion
    case id
    case inode
    case lastResponseHeaders
    case lastRetrievedAt
    case partialFileURL
    case prefixSHA256
    case reference
  }
}
