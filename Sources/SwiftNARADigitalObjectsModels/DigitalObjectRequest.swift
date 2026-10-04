/// A reusable digital object operation with an inspectable value resolution.
///
/// A request holds only values: creating, storing, or comparing one performs no I/O and holds
/// no transport closure.
/// ```swift
/// let request = DigitalObjectRequest.download(reference)
/// ```
public struct DigitalObjectRequest<Response>: Hashable, Sendable {
  /// The operation to execute, with no transport closure or hidden I/O.
  public enum Resolution: Hashable, Sendable {
    /// One independently executable endpoint.
    case endpoint(Endpoint<Response>)
  }

  /// The complete operation description.
  public let resolution: Resolution

  /// Describes one consumer-defined endpoint.
  /// - Parameter endpoint: The independently executable operation.
  public init(endpoint: Endpoint<Response>) { resolution = .endpoint(endpoint) }
}

extension DigitalObjectRequest where Response == DigitalObjectRangeReceipt {
  /// Describes one validated partial-original operation without I/O.
  /// - Parameters:
  ///   - range: One explicit inclusive byte interval.
  ///   - reference: Known original identity, validator and complete length.
  /// - Returns: An independently executable range operation.
  public static func range(
    _ range: DigitalObjectByteRange, of reference: DigitalObjectRangeReference
  ) -> Self {
    Self(endpoint: .range(range, of: reference))
  }
}

extension DigitalObjectRequest where Response == DigitalObjectReceipt {
  /// Describes the download of one digital object, independently of its destination file.
  ///
  /// The request resolves to ``DigitalObjectRequest/Resolution/endpoint(_:)`` with the same
  /// endpoint as ``Endpoint/download(_:)``.
  /// ```swift
  /// let request = DigitalObjectRequest.download(reference)
  /// ```
  /// - Parameter reference: A validated digital object reference.
  /// - Returns: An immutable download request.
  public static func download(_ reference: DigitalObjectReference) -> Self {
    Self(endpoint: .download(reference))
  }
}

extension DigitalObjectRequest where Response == IIIFImageInformation {
  /// Describes one bounded image-information operation.
  /// - Parameter reference: The expected service identity.
  /// - Returns: A reusable value request with no construction I/O.
  public static func imageInformation(_ reference: IIIFImageReference) -> Self {
    Self(endpoint: .imageInformation(reference))
  }
}

extension DigitalObjectRequest where Response == IIIFImageReceipt {
  /// Describes a validated full-image JPEG derivative without performing I/O.
  /// - Parameter request: Previously validated information and resize parameters.
  /// - Returns: An independently executable derivative operation.
  public static func image(_ request: IIIFImageRequest) -> Self {
    Self(endpoint: .image(request))
  }
}
