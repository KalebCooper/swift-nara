#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// Complete acquired ZIP bytes and their source and local-integrity evidence.
///
/// This receipt does not validate ZIP structure or entries, extract files, or certify a
/// coherent release across multiple archives. Keep the file immutable during local reading.
public struct BulkArchiveReceipt: Codable, Hashable, Sendable {
  /// The complete saved byte count.
  public let byteCount: Int64
  /// Retained resume state, or nil for a one-request acquisition.
  public let checkpoint: BulkDownloadCheckpoint?
  /// The complete local archive.
  public let fileURL: URL
  /// The selected archive key and optional version pin.
  public let reference: BulkArchiveReference
  /// The complete HTTP 200 response, or the final validated 206 range's evidence.
  public let retrieval: SourceRetrieval
  /// SHA-256 of the complete local bytes, independent of S3 ETag semantics.
  public let sha256: String

  /// Restores receipt evidence without inspecting the local file.
  /// - Parameter decoder: Persisted receipt data.
  /// - Throws: A decoding error for inconsistent identity, lengths, digest or local URL.
  public init(from decoder: any Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    byteCount = try c.decode(Int64.self, forKey: .byteCount)
    checkpoint = try c.decodeIfPresent(BulkDownloadCheckpoint.self, forKey: .checkpoint)
    fileURL = try c.decode(URL.self, forKey: .fileURL)
    reference = try c.decode(BulkArchiveReference.self, forKey: .reference)
    retrieval = try c.decode(SourceRetrieval.self, forKey: .retrieval)
    sha256 = try c.decode(String.self, forKey: .sha256)
    guard byteCount > 0, sha256.utf8.count == 64,
      sha256.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }),
      fileURL.isFileURL, fileURL.standardizedFileURL == fileURL,
      fileURL.host == nil || fileURL.host == "",
      fileURL.user == nil, fileURL.password == nil, fileURL.port == nil,
      fileURL.query == nil, fileURL.fragment == nil,
      retrieval.url == reference.url,
      retrieval.status == (checkpoint == nil ? 200 : 206),
      checkpoint.map({
        $0.committedByteCount == byteCount && $0.reference.totalByteCount == byteCount
          && $0.reference.key == reference.key && $0.reference.versionID == reference.versionID
          && $0.prefixSHA256 == sha256 && $0.lastResponseHeaders == retrieval.headers
          && $0.lastRetrievedAt == retrieval.retrievedAt
      }) ?? true
    else {
      throw DecodingError.dataCorrupted(
        .init(
          codingPath: decoder.codingPath,
          debugDescription: "Inconsistent archive acquisition receipt."))
    }
  }

  package init(
    byteCount: Int64, checkpoint: BulkDownloadCheckpoint?, fileURL: URL,
    reference: BulkArchiveReference, retrieval: SourceRetrieval, sha256: String
  ) {
    self.byteCount = byteCount
    self.checkpoint = checkpoint
    self.fileURL = fileURL
    self.reference = reference
    self.retrieval = retrieval
    self.sha256 = sha256
  }

  private enum CodingKeys: String, CodingKey {
    case byteCount
    case checkpoint
    case fileURL
    case reference
    case retrieval
    case sha256
  }
}
