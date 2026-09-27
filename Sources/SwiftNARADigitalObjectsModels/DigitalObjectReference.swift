#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// A bulk digital object's identity and its validated public transport path.
///
/// A reference keeps the bulk export's `objectUrl` string byte for byte in ``url`` and derives
/// ``transportPath`` on ``transportOrigin`` by a fixed prefix mapping:
///
/// | Accepted `url` prefix | Transport path prefix |
/// | --- | --- |
/// | `https://s3.amazonaws.com/NARAprodstorage/lz/` | `/medialz/` |
/// | `https://s3.amazonaws.com/NARAprodstorage/opastorage/live/` | `/medialive/` |
/// | `https://catalog.archives.gov/medialz/` | `/medialz/` |
/// | `https://catalog.archives.gov/medialive/` | `/medialive/` |
///
/// The remainder after the prefix is carried over unchanged, percent escapes included. This
/// mapping is how NARA's Catalog site loads bulk-linked objects; it is observed practice, not a
/// published contract. Any other URL is refused with a ``DigitalObjectReferenceError`` rather than
/// passed through or rewritten, so no reference ever names another origin. Regional, dualstack,
/// and virtual-hosted spellings of the bucket host are refused until a bulk export evidences them.
///
/// Creating, encoding, or decoding a reference performs no I/O and does not show that the object
/// exists, is retrievable, or may be reused. Identifiers are kept exactly as supplied.
/// ```swift
/// let reference = try DigitalObjectReference(
///   naID: "122178160", objectID: "122178162",
///   url: "https://s3.amazonaws.com/NARAprodstorage/lz/presidential-libraries/roosevelt/577534/msf00611_Page_01.jpg")
/// print(reference.transportPath)
/// // /medialz/presidential-libraries/roosevelt/577534/msf00611_Page_01.jpg
/// ```
public struct DigitalObjectReference: Codable, Hashable, Sendable {
  /// The National Archives Identifier of the description that lists the object, as supplied.
  public let naID: String
  /// The bulk `objectId`, as supplied, or `nil` when the source object has none.
  public let objectID: String?
  /// The percent-encoded absolute path of the object on ``transportOrigin``.
  public let transportPath: String
  /// The original digital object URL string, unchanged.
  public let url: String

  /// The only origin a transport path is relative to.
  public static var transportOrigin: String { "https://catalog.archives.gov" }

  /// The full transport URL: ``transportOrigin`` followed by ``transportPath``.
  public var transportURL: URL {
    guard let url = URL(string: Self.transportOrigin + transportPath) else {
      preconditionFailure("A validated ASCII path forms a URL with the fixed HTTPS origin.")
    }
    return url
  }

  /// Creates a reference by validating a digital object URL, without any request.
  ///
  /// Validation runs in this order and throws the first failure: parsing, scheme, user
  /// information, host and port, fragment, query, exact spelling, path prefix, empty remainder,
  /// dot segments, then the remaining path segment rules.
  /// - Parameters:
  ///   - naID: The National Archives Identifier of the description that lists the object.
  ///   - objectID: The bulk `objectId`, or `nil` when the source object has none.
  ///   - url: The digital object URL, normally a bulk `objectUrl`, kept unchanged.
  /// - Throws: ``DigitalObjectReferenceError/malformedURL`` for an unparseable URL or one whose
  ///   parts do not spell it exactly; ``DigitalObjectReferenceError/unsupportedScheme``,
  ///   ``DigitalObjectReferenceError/userInfo``,
  ///   ``DigitalObjectReferenceError/unsupportedOrigin``,
  ///   ``DigitalObjectReferenceError/fragment``, or ``DigitalObjectReferenceError/query`` for
  ///   those URL parts; ``DigitalObjectReferenceError/unsupportedPath`` outside the accepted
  ///   prefixes; ``DigitalObjectReferenceError/emptyRemainder`` when no object follows the
  ///   prefix; ``DigitalObjectReferenceError/traversal`` for a `.` or `..` segment; and
  ///   ``DigitalObjectReferenceError/malformedPath`` for any other invalid segment.
  public init(naID: String, objectID: String?, url: String) throws(DigitalObjectReferenceError) {
    guard let components = URLComponents(string: url) else { throw .malformedURL }
    guard components.scheme == "https" else { throw .unsupportedScheme }
    guard components.percentEncodedUser == nil, components.percentEncodedPassword == nil else {
      throw .userInfo
    }
    guard let host = components.percentEncodedHost, components.port == nil,
      let mappings = Self.mappings[host]
    else { throw .unsupportedOrigin }
    guard components.percentEncodedFragment == nil else { throw .fragment }
    guard components.percentEncodedQuery == nil else { throw .query }
    let path = components.percentEncodedPath
    guard "https://" + host + path == url else { throw .malformedURL }
    guard let mapping = mappings.first(where: { path.hasPrefix($0.source) }) else {
      throw .unsupportedPath
    }
    let remainder = String(path.dropFirst(mapping.source.count))
    guard !remainder.isEmpty else { throw .emptyRemainder }
    let segments = remainder.split(separator: "/", omittingEmptySubsequences: false)
    for segment in segments {
      if let value = Self.decoded(segment), value == "." || value == ".." { throw .traversal }
    }
    for segment in segments {
      guard !segment.isEmpty, segment.utf8.allSatisfy({ Self.segmentBytes.contains($0) }),
        let value = Self.decoded(segment),
        !value.unicodeScalars.contains(where: {
          $0 == "/" || $0 == "\\" || $0.value < 32 || $0.value == 127
        })
      else { throw .malformedPath }
    }
    self.naID = naID
    self.objectID = objectID
    self.transportPath = mapping.transport + remainder
    self.url = url
  }

  /// Decodes a reference and validates its URL again.
  ///
  /// Only `naID`, `objectID`, and `url` are read; the transport path is always derived.
  /// - Parameter decoder: The decoder to read from.
  /// - Throws: `DecodingError.dataCorrupted` with the ``DigitalObjectReferenceError`` as its
  ///   underlying error when the URL is refused, or the decoder's error for a missing or
  ///   mistyped value.
  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let naID = try container.decode(String.self, forKey: .naID)
    let objectID = try container.decodeIfPresent(String.self, forKey: .objectID)
    let url = try container.decode(String.self, forKey: .url)
    do {
      try self.init(naID: naID, objectID: objectID, url: url)
    } catch {
      throw DecodingError.dataCorrupted(
        DecodingError.Context(
          codingPath: container.codingPath + [CodingKeys.url],
          debugDescription: "The URL is outside the digital object origin policy.",
          underlyingError: error))
    }
  }

  /// Encodes the identifiers and the original URL; a `nil` object identifier is omitted.
  /// - Parameter encoder: The encoder to write to.
  /// - Throws: The encoder's error.
  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(naID, forKey: .naID)
    try container.encodeIfPresent(objectID, forKey: .objectID)
    try container.encode(url, forKey: .url)
  }

  private enum CodingKeys: String, CodingKey {
    case naID
    case objectID
    case url
  }

  /// Accepted path prefixes per exact host, each with its transport path prefix.
  private static let mappings: [String: [(source: String, transport: String)]] = [
    "catalog.archives.gov": [
      (source: "/medialive/", transport: "/medialive/"),
      (source: "/medialz/", transport: "/medialz/"),
    ],
    "s3.amazonaws.com": [
      (source: "/NARAprodstorage/lz/", transport: "/medialz/"),
      (source: "/NARAprodstorage/opastorage/live/", transport: "/medialive/"),
    ],
  ]

  /// Bytes permitted in an encoded path segment: unreserved, sub-delimiters, `:`, `@`, and `%`.
  private static let segmentBytes = Set(
    "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~!$&'()*+,;=:@%".utf8)

  /// Percent-decodes one segment, or returns `nil` for a malformed escape or invalid UTF-8.
  private static func decoded(_ segment: Substring) -> String? {
    let bytes = Array(segment.utf8)
    var result: [UInt8] = []
    var index = 0
    while index < bytes.count {
      if bytes[index] == UInt8(ascii: "%") {
        guard index + 2 < bytes.count, let high = hexValue(bytes[index + 1]),
          let low = hexValue(bytes[index + 2])
        else { return nil }
        result.append(high << 4 | low)
        index += 3
      } else {
        result.append(bytes[index])
        index += 1
      }
    }
    return String(validating: result, as: UTF8.self)
  }

  /// The value of one ASCII hexadecimal digit, or `nil` for any other byte.
  private static func hexValue(_ byte: UInt8) -> UInt8? {
    switch byte {
    case UInt8(ascii: "0")...UInt8(ascii: "9"): byte - UInt8(ascii: "0")
    case UInt8(ascii: "A")...UInt8(ascii: "F"): byte - UInt8(ascii: "A") + 10
    case UInt8(ascii: "a")...UInt8(ascii: "f"): byte - UInt8(ascii: "a") + 10
    default: nil
    }
  }
}
