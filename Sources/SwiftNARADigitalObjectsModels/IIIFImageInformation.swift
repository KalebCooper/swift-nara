#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// Validated IIIF Image API 3 information with original bytes and retrieval evidence.
///
/// Unknown fields, nulls, feature codes and JSON-LD contexts remain in `rawBytes`.
/// Contexts and linked services are never dereferenced. A decoded document proves
/// neither availability of every advertised representation nor media reuse rights.
public struct IIIFImageInformation: Hashable, Sendable {
  /// A preferred image size declared by the service.
  public struct Size: Decodable, Hashable, Sendable {
    /// Declared height in pixels.
    public let height: Int
    /// Declared width in pixels.
    public let width: Int
  }

  /// A tile declaration preserved as metadata; this package does not request tiles.
  public struct Tile: Decodable, Hashable, Sendable {
    /// Declared tile height, absent when the source omits it.
    public let height: Int?
    /// Declared scale factors, preserving source order.
    public let scaleFactors: [Int]
    /// Declared tile width.
    public let width: Int
  }

  /// Optional additional feature codes, including unknown codes.
  public var extraFeatures: [String]? { document.extraFeatures }
  /// Optional additional format codes.
  public var extraFormats: [String]? { document.extraFormats }
  /// Optional additional quality codes.
  public var extraQualities: [String]? { document.extraQualities }
  /// Received headers in source order; empty for local decoding without HTTP evidence.
  public let headers: [DigitalObjectReceipt.Header]
  /// Full image height in pixels.
  public var height: Int { document.height }
  /// The validated identity, exactly matching the requested service.
  public var id: String { document.id }
  /// Optional maximum output area; absence is preserved.
  public var maxArea: Int? { document.maxArea }
  /// Optional maximum height as published, without synthesizing a missing field.
  public var maxHeight: Int? { document.maxHeight }
  /// Optional maximum width as published.
  public var maxWidth: Int? { document.maxWidth }
  /// The declared compliance profile, including an unknown future value.
  public var profile: String { document.profile }
  /// The unchanged information response bytes, including unknown and null members.
  public let rawBytes: Data
  /// The original source and expected service identity.
  public let reference: IIIFImageReference
  /// An injected retrieval instant, or nil for local decoding without one.
  public let retrievedAt: Date?
  /// Optional preferred sizes in source order.
  public var sizes: [Size]? { document.sizes }
  /// The information source URL derived from the validated reference.
  public var sourceURL: URL { reference.informationURL }
  /// HTTP status, or nil when no HTTP evidence was supplied.
  public let status: Int?
  /// Optional tile descriptions, with no tile fetching behavior.
  public var tiles: [Tile]? { document.tiles }
  /// Full image width in pixels.
  public var width: Int { document.width }

  private let document: Document

  /// Decodes bounded information without network or file access.
  /// - Parameters:
  ///   - data: Original JSON information bytes.
  ///   - headers: Received headers, if available.
  ///   - maximumBytes: Positive decoding budget; defaults to one MiB.
  ///   - reference: The expected service and original source identity.
  ///   - retrievedAt: An optional caller-supplied retrieval instant.
  ///   - status: Optional received HTTP status.
  /// - Returns: Validated information retaining every original byte.
  /// - Throws: `IIIFImageError` for invalid shapes, identities, versions, or byte limits.
  public static func decode(
    _ data: Data, headers: [DigitalObjectReceipt.Header] = [], maximumBytes: Int = 1_048_576,
    reference: IIIFImageReference, retrievedAt: Date? = nil, status: Int? = nil
  ) throws(IIIFImageError) -> Self {
    guard maximumBytes > 0, data.count <= maximumBytes else { throw .limitExceeded }
    let document: Document
    do { document = try JSONDecoder().decode(Document.self, from: data) } catch {
      throw .malformedInformation
    }
    guard document.type == "ImageService3", document.protocol == "http://iiif.io/api/image"
    else { throw .unsupportedFeature }
    guard document.id == reference.serviceURL.absoluteString,
      document.height > 0, document.width > 0, !document.profile.isEmpty,
      [document.maxArea, document.maxHeight, document.maxWidth].allSatisfy({
        $0 == nil || ($0 ?? 0) > 0
      }),
      document.maxHeight == nil || document.maxWidth != nil,
      document.sizes?.allSatisfy({ $0.height > 0 && $0.width > 0 }) != false,
      document.tiles?.allSatisfy({
        $0.width > 0 && ($0.height == nil || ($0.height ?? 0) > 0)
          && !$0.scaleFactors.isEmpty && $0.scaleFactors.allSatisfy { $0 > 0 }
      }) != false
    else { throw .malformedInformation }
    return Self(
      headers: headers, rawBytes: data, reference: reference, retrievedAt: retrievedAt,
      status: status, document: document)
  }

  private struct Document: Decodable, Hashable, Sendable {
    let extraFeatures: [String]?
    let extraFormats: [String]?
    let extraQualities: [String]?
    let height: Int
    let id: String
    let maxArea: Int?
    let maxHeight: Int?
    let maxWidth: Int?
    let profile: String
    let `protocol`: String
    let sizes: [Size]?
    let tiles: [Tile]?
    let type: String
    let width: Int
  }
}
