#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// A malformed or oversized bulk source document.
public enum CatalogDecodingError: Error, Hashable, Sendable {
  /// The input exceeds its configured byte or nesting limit.
  case limitExceeded
  /// The JSON document is malformed or lacks a record identifier.
  case malformedJSON
  /// The XML is malformed, ambiguous, or outside the supported S3 format.
  case malformedXML
}
