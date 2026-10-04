/// A positive full-image resize, validated against information when a request is created.
///
/// Width and height preserve aspect ratio; fit uses a bounding box. No form requests
/// upscaling. The maximum form asks the server for its largest permitted representation.
public struct IIIFImageSize: Hashable, Sendable {
  /// The version-3 `max` size, which can be smaller than the original dimensions.
  public static let maximum = Self(height: nil, kind: .maximum, width: nil)

  /// The exact IIIF size parameter, without surrounding path separators.
  public var parameter: String {
    switch kind {
    case .fit: "!\(width ?? 0),\(height ?? 0)"
    case .height: ",\(height ?? 0)"
    case .maximum: "max"
    case .width: "\(width ?? 0),"
    }
  }

  private let height: Int?
  private let kind: Kind
  private let width: Int?

  /// Fits within a positive bounding box without cropping or distortion.
  /// - Parameters:
  ///   - height: Positive bounding height in pixels.
  ///   - width: Positive bounding width in pixels.
  /// - Returns: A size awaiting validation against an information document.
  /// - Throws: `IIIFImageError.invalidSize` for nonpositive dimensions.
  public static func fit(height: Int, width: Int) throws(IIIFImageError) -> Self {
    guard height > 0, width > 0 else { throw .invalidSize }
    return Self(height: height, kind: .fit, width: width)
  }

  /// Selects a positive output height while preserving aspect ratio.
  /// - Parameter pixels: Positive height in pixels.
  /// - Returns: A size awaiting source-limit validation.
  /// - Throws: `IIIFImageError.invalidSize` for a nonpositive height.
  public static func height(_ pixels: Int) throws(IIIFImageError) -> Self {
    guard pixels > 0 else { throw .invalidSize }
    return Self(height: pixels, kind: .height, width: nil)
  }

  /// Selects a positive output width while preserving aspect ratio.
  /// - Parameter pixels: Positive width in pixels.
  /// - Returns: A size awaiting source-limit validation.
  /// - Throws: `IIIFImageError.invalidSize` for a nonpositive width.
  public static func width(_ pixels: Int) throws(IIIFImageError) -> Self {
    guard pixels > 0 else { throw .invalidSize }
    return Self(height: nil, kind: .width, width: pixels)
  }

  package func validate(_ information: IIIFImageInformation) throws(IIIFImageError) {
    guard ["level0", "level1", "level2"].contains(information.profile) else {
      throw .unsupportedFeature
    }
    if kind == .maximum { return }
    let feature: String
    switch kind {
    case .fit: feature = "sizeByConfinedWh"
    case .height: feature = "sizeByH"
    case .maximum: return
    case .width: feature = "sizeByW"
    }
    guard
      information.profile == "level2"
        || (information.profile == "level1" && kind != .fit)
        || information.extraFeatures?.contains(feature) == true
    else { throw .unsupportedFeature }
    guard (width ?? 1) <= information.width, (height ?? 1) <= information.height else {
      throw .invalidSize
    }
    let outputHeight: Int
    let outputWidth: Int
    if kind == .height {
      outputHeight = height ?? 1
      outputWidth = try Self.scaled(information.width, by: outputHeight, over: information.height)
    } else if kind == .width {
      outputWidth = width ?? 1
      outputHeight = try Self.scaled(information.height, by: outputWidth, over: information.width)
    } else {
      let boundedWidth = width ?? 1
      let boundedHeight = height ?? 1
      let heightAtWidth = try Self.scaled(
        information.height, by: boundedWidth, over: information.width)
      if heightAtWidth <= boundedHeight {
        outputHeight = heightAtWidth
        outputWidth = boundedWidth
      } else {
        outputHeight = boundedHeight
        outputWidth = try Self.scaled(
          information.width, by: boundedHeight, over: information.height)
      }
    }
    guard outputWidth <= (information.maxWidth ?? information.width),
      outputHeight <= (information.maxHeight ?? information.maxWidth ?? information.height)
    else { throw .limitExceeded }
    if let area = information.maxArea, outputWidth > area / outputHeight {
      throw .limitExceeded
    }
  }

  private enum Kind: Hashable, Sendable {
    case fit
    case height
    case maximum
    case width
  }

  /// Rounds upward so validation never understates a potentially rounded output dimension.
  private static func scaled(_ value: Int, by factor: Int, over divisor: Int)
    throws(IIIFImageError) -> Int
  {
    let product = value.multipliedReportingOverflow(by: factor)
    guard !product.overflow else { throw .limitExceeded }
    let quotient = product.partialValue / divisor
    return quotient + (product.partialValue % divisor == 0 ? 0 : 1)
  }
}
