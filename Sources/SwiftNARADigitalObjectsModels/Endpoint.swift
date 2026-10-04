#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// One validated digital object operation on the public NARA Catalog origin.
///
/// Endpoints contain only values and send nothing at construction. Original downloads use
/// validated `/medialz/` or `/medialive/` paths; IIIF factories derive an operation beneath
/// `/iiif/3/` from a validated source reference. Every path stays on ``origin``.
/// Creating an endpoint does not show that the object exists, is retrievable, or may be reused.
///
/// The bulk models module declares its own `Endpoint`; qualify the type by module, as in
/// `SwiftNARADigitalObjectsModels.Endpoint`, in a file that imports both.
/// ```swift
/// let reference = try DigitalObjectReference(
///   naID: "122178160", objectID: "122178162",
///   url: "https://s3.amazonaws.com/NARAprodstorage/lz/presidential-libraries/roosevelt/577534/msf00611_Page_01.jpg")
/// let endpoint = Endpoint.download(reference)
/// print(endpoint.url)
/// // https://catalog.archives.gov/medialz/presidential-libraries/roosevelt/577534/msf00611_Page_01.jpg
/// ```
public struct Endpoint<Response>: Hashable, Sendable {
  /// The representation selected for a resumable original download, otherwise nil.
  public private(set) var downloadReference: DigitalObjectRangeReference? = nil
  /// The IIIF reference for an information operation, otherwise nil.
  public private(set) var imageReference: IIIFImageReference? = nil
  /// The validated derivative transform, otherwise nil.
  public private(set) var imageRequest: IIIFImageRequest? = nil
  /// The exact encoded object path relative to ``origin``.
  public let path: String
  /// The selected byte interval for a range operation, otherwise nil.
  public private(set) var range: DigitalObjectByteRange? = nil
  /// The known original representation for a range operation, otherwise nil.
  public private(set) var rangeReference: DigitalObjectRangeReference? = nil
  /// The reference when this endpoint was created by the download factory, or `nil` when it
  /// was created from a link.
  public private(set) var reference: DigitalObjectReference? = nil

  /// The only origin every endpoint path is relative to.
  public static var origin: String { DigitalObjectReference.transportOrigin }

  /// The full transport URL: ``origin`` followed by ``path``.
  public var url: URL {
    guard let url = URL(string: Self.origin + path) else {
      preconditionFailure("A validated ASCII path forms a URL with the fixed HTTPS origin.")
    }
    return url
  }

  /// Creates an endpoint from a digital object URL on ``origin``, without any request.
  ///
  /// The link must begin exactly with `https://catalog.archives.gov/` and name a `/medialz/`
  /// or `/medialive/` object. A link on another origin, including a bulk `NARAprodstorage`
  /// URL, or with a user name, password, port, query, or fragment is refused, as is any path
  /// ``DigitalObjectReference`` refuses. The resulting endpoint has no ``reference``.
  /// - Parameter link: A digital object URL on the public Catalog origin.
  public init?(link: URL) {
    let string = link.absoluteString
    guard string.hasPrefix(Self.origin + "/"),
      let path = try? DigitalObjectReference.transportPath(for: string)
    else { return nil }
    self.path = path
  }

  private init(downloadReference: DigitalObjectRangeReference) {
    self.downloadReference = downloadReference
    path = downloadReference.object.transportPath
  }

  package init(imageReference: IIIFImageReference) {
    self.imageReference = imageReference
    path = imageReference.servicePath + "/info.json"
  }

  private init(imageRequest: IIIFImageRequest) {
    self.imageRequest = imageRequest
    path = imageRequest.path
  }

  private init(range: DigitalObjectByteRange, reference: DigitalObjectRangeReference) {
    path = reference.object.transportPath
    self.range = range
    rangeReference = reference
  }

  private init(reference: DigitalObjectReference) {
    path = reference.transportPath
    self.reference = reference
  }
}

extension Endpoint where Response == DigitalObjectDownloadReceipt {
  /// Describes serial validated ranges without capturing a local file or performing I/O.
  /// - Parameter reference: The exact known original representation.
  /// - Returns: An independently executable resumable-download endpoint.
  public static func resumableDownload(_ reference: DigitalObjectRangeReference) -> Self {
    Self(downloadReference: reference)
  }
}

extension Endpoint where Response == DigitalObjectRangeReceipt {
  /// Describes one validated partial-original operation without I/O.
  /// - Parameters:
  ///   - range: One explicit inclusive byte interval.
  ///   - reference: Known original identity, validator and complete length.
  /// - Returns: An independently executable range operation.
  public static func range(
    _ range: DigitalObjectByteRange, of reference: DigitalObjectRangeReference
  ) -> Self {
    Self(range: range, reference: reference)
  }
}

extension Endpoint where Response == DigitalObjectReceipt {
  /// Describes the download of one digital object from its validated transport path.
  ///
  /// The path is the reference's ``DigitalObjectReference/transportPath`` and the reference is
  /// kept in ``Endpoint/reference`` for the receipt. Creating the endpoint sends nothing.
  /// ```swift
  /// let endpoint = Endpoint.download(reference)
  /// ```
  /// - Parameter reference: A validated digital object reference.
  /// - Returns: An independently executable download endpoint.
  public static func download(_ reference: DigitalObjectReference) -> Self {
    Self(reference: reference)
  }
}

extension Endpoint where Response == IIIFImageInformation {
  /// Describes one IIIF information request without performing I/O.
  /// - Parameter reference: The validated image service reference.
  /// - Returns: An independently executable information endpoint.
  public static func imageInformation(_ reference: IIIFImageReference) -> Self {
    Self(imageReference: reference)
  }
}

extension Endpoint where Response == IIIFImageReceipt {
  /// Describes a validated full-image JPEG derivative without performing I/O.
  /// - Parameter request: Previously validated information and resize parameters.
  /// - Returns: An independently executable derivative operation.
  public static func image(_ request: IIIFImageRequest) -> Self {
    Self(imageRequest: request)
  }
}
