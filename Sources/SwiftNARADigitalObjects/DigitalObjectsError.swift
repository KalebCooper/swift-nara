import Foundation
// Public initializers and failures name Transport and TransportError.
@_exported import HTTPCore
import HTTPTypes
import SwiftNARADigitalObjectsModels

/// A typed digital-object retrieval or local publication failure.
public enum DigitalObjectsError: Error {
  /// The requesting task was cancelled; no complete file was published.
  case cancelled
  /// The retained download's local state does not permit safe continuation.
  case downloadState(DigitalObjectDownloadStateError)
  /// A successful status carried the observed CloudFront Error marker.
  ///
  /// Bytes are bounded by the caller's diagnostic limit. A true truncation flag means
  /// additional bytes were observed but omitted. Marker absence does not establish authenticity.
  case errorPage(body: Data, code: Int, headers: HTTPFields, isTruncated: Bool)
  /// Local file access failed; complete publication is not confirmed.
  case file(any Error)
  /// A IIIF information document or requested transform is invalid.
  case information(IIIFImageError)
  /// A byte bound, caller identity, or destination URL is invalid.
  case invalidConfiguration
  /// A derivative has a non-JPEG media type or lacks the JPEG start signature.
  case invalidImage
  /// The response exceeds the caller's whole-object bound.
  case limitExceeded
  /// A byte interval or partial representation does not meet the range contract.
  case range(DigitalObjectRangeError)
  /// Whole-body status, encoding, content range, or byte length is inconsistent.
  case sizeMismatch
  /// HTTP or transport failure, with bounded status-body evidence and received headers.
  case transport(TransportError)
}
