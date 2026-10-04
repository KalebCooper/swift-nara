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
  /// The complete source OCR text, when present, without replacing `extractedText`.
  public var completeExtractedText: String? { source["completeExtractedText"]?.string }
  /// The original OCR text, if supplied as text.
  public var extractedText: String? { source["extractedText"]?.string }
  /// The source's declared OCR accuracy, using its `extractedTextAccurracy` spelling.
  ///
  /// This exact integer is not clamped to a percentage range or independently verified.
  /// Missing, null, and noninteger values return nil and remain inspectable in `source`.
  public var extractedTextAccuracy: Int? { source["extractedTextAccurracy"]?.exactInteger }
  /// The source description of this object, without inferring page availability.
  public var objectDescription: String? { source["objectDescription"]?.string }
  /// The source's object designator, without interpreting it as a page number.
  public var objectDesignator: String? { source["objectDesignator"]?.string }
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
  /// Text attributed by the source schema to NARA partners, kept separate from source OCR.
  public var otherExtractedText: String? { source["otherExtractedText"]?.string }
  /// The original thumbnail link, without validating its host or fetching its content.
  public var thumbnailURL: String? { source["thumbnailUrl"]?.string }
}
