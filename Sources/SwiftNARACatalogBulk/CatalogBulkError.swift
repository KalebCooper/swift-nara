// Public client initializers and failures name Transport and TransportError.
@_exported import HTTPCore
import SwiftNARACatalogBulkModels

/// A typed bulk-source, file, recording, or transport failure.
public enum CatalogBulkError: Error {
  /// The reading task was cancelled.
  case cancelled
  /// A bounded source document could not be decoded.
  case decoding(CatalogDecodingError)
  /// Local file access failed; no complete download is published.
  case file(any Error)
  /// A caller supplied an invalid size bound or non-file destination.
  case invalidConfiguration
  /// The shard exceeded its configured total byte bound.
  case limitExceeded
  /// A physical JSONL line was oversized or malformed, with its exact location.
  case line(byteOffset: Int64, lineNumber: Int64, reason: CatalogDecodingError)
  /// The S3 listing did not provide valid forward progress.
  case pagination(ManifestError)
  /// The caller's response recorder failed; that page is not yielded.
  case recording(any Error)
  /// Received file bytes disagree with the declared receipt or content length.
  case sizeMismatch
  /// The HTTP exchange failed, retaining source status and headers when available.
  case transport(TransportError)

  init(_ error: TransportError) {
    if case .cancelled = error {
      self = .cancelled
    } else if let decoding = error.underlying as? CatalogDecodingError {
      self = .decoding(decoding)
    } else {
      self = .transport(error)
    }
  }
}
