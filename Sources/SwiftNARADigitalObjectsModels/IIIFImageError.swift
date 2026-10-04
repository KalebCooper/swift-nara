/// A refused IIIF information document or requested image size.
public enum IIIFImageError: Error, Hashable, Sendable {
  /// The requested size exceeds source dimensions or advertised limits.
  case invalidSize
  /// Information bytes exceed the caller's decoding limit.
  case limitExceeded
  /// Required information, dimensions, or service identity are invalid.
  case malformedInformation
  /// The information describes an unsupported version, profile, or feature.
  case unsupportedFeature
}
