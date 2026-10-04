#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// A version-3 image service derived from one validated original-file reference.
///
/// The source key is decoded once and encoded as one identifier segment. No
/// information, JSON-LD context, linked service, or original file is fetched.
public struct IIIFImageReference: Hashable, Sendable {
  /// The original identity and source URL, separate from the IIIF service.
  public let reference: DigitalObjectReference
  /// The service path including its single percent-encoded identifier.
  public let servicePath: String

  /// The information URL, without performing I/O.
  public var informationURL: URL { serviceURL.appendingPathComponent("info.json") }
  /// The exact supported service identity.
  public var serviceURL: URL {
    guard let value = URL(string: DigitalObjectReference.transportOrigin + servicePath) else {
      preconditionFailure("A validated encoded identifier forms a URL.")
    }
    return value
  }

  /// Derives the observed NARA IIIF mapping from a validated media reference.
  /// - Parameter reference: An original object on either supported storage prefix.
  public init(reference: DigitalObjectReference) {
    self.reference = reference
    let path = reference.transportPath
    let key =
      path.hasPrefix("/medialz/")
      ? "lz/" + path.dropFirst("/medialz/".count)
      : "opastorage/live/" + path.dropFirst("/medialive/".count)
    var components = URLComponents()
    components.percentEncodedPath = "/" + key
    let unreserved = Set(
      "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~".utf8)
    let encoded = components.path.dropFirst().utf8.map { byte in
      if unreserved.contains(byte) { return String(UnicodeScalar(byte)) }
      let hex = String(byte, radix: 16, uppercase: true)
      return "%" + (hex.count == 1 ? "0" : "") + hex
    }.joined()
    servicePath = "/iiif/3/" + encoded
  }
}
