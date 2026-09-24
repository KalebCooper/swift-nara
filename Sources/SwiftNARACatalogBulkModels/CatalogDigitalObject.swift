#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// One digital object and its original metadata, without fetching its URL.
///
/// Extracted text is source OCR, not a verified transcription. All attribution and contribution
/// fields remain in `source`; object availability does not grant reuse rights.
public struct CatalogDigitalObject: Codable, Hashable, Sendable {
  /// Every source field for the object, including unknown OCR attribution.
  public let source: JSONValue
  /// Creates a projection without changing the original source value.
  public init(source: JSONValue) { self.source = source }
  /// The original OCR text, if supplied as text.
  public var extractedText: String? { source["extractedText"]?.string }
  /// The original file name.
  public var objectFilename: String? { source["objectFilename"]?.string }
  /// The declared file size, retaining its JSON representation.
  public var objectFileSize: JSONValue? { source["objectFileSize"] }
  /// The exact source digital-object identifier.
  public var objectID: String? { source["objectId"]?.identifier }
  /// The open source object format/type.
  public var objectType: String? { source["objectType"]?.string }
  /// The source URL string, preserved even if it is not a valid URL.
  public var objectURL: String? { source["objectUrl"]?.string }
}
