#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// One full-region, unrotated, default-quality JPEG request with validated size limits.
///
/// Construction performs no I/O and requires previously decoded information. Unknown
/// profiles and unsupported features fail. Width, height and fit bounds must not exceed
/// original dimensions. Conservative upward rounding checks server limits without
/// silently clamping a requested size. Maximum delegates sizing to the server's `max`.
public struct IIIFImageRequest: Hashable, Sendable {
  /// The exact information and source evidence used to validate the request.
  public let information: IIIFImageInformation
  /// The requested transform, separate from the server's eventual image bytes.
  public let size: IIIFImageSize

  /// The fixed-origin path; no arbitrary region, rotation, format or query is accepted.
  public var path: String {
    information.reference.servicePath + "/full/" + size.parameter + "/0/default.jpg"
  }
  /// The complete validated derivative URL.
  public var url: URL {
    guard let value = URL(string: DigitalObjectReference.transportOrigin + path) else {
      preconditionFailure("A validated image path forms a URL.")
    }
    return value
  }

  /// Validates a resize against the supplied information, without fetching anything.
  /// - Parameters:
  ///   - information: Previously validated information for the source image.
  ///   - size: Positive requested size or server maximum.
  /// - Throws: `IIIFImageError` for upscaling, unsupported features, or exceeded limits.
  public init(information: IIIFImageInformation, size: IIIFImageSize) throws(IIIFImageError) {
    try size.validate(information)
    self.information = information
    self.size = size
  }
}
