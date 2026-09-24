#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// One validated operation on the official NARA bulk bucket.
///
/// Endpoints contain only values and send nothing at construction.
/// ```swift
/// let endpoint = Endpoint.manifest(try ManifestQuery(maxKeys: 4, prefix: "descriptions/"))
/// ```
public struct Endpoint<Response>: Hashable, Sendable {
  /// The exact query when this endpoint was created by the manifest factory.
  public private(set) var manifestQuery: ManifestQuery? = nil
  /// The public bucket origin used by every endpoint.
  public static var origin: String { "https://nara-national-archives-catalog.s3.amazonaws.com" }
  /// The exact encoded path and query relative to the bucket origin.
  public let path: String

  /// The full source URL, with its original encoded query.
  public var url: URL {
    guard let url = URL(string: Self.origin + path) else {
      preconditionFailure("Validated ASCII paths form a URL with the fixed HTTPS origin.")
    }
    return url
  }

  /// Creates an endpoint from a same-origin HTTPS URL.
  /// - Parameter link: A bucket URL without credentials, fragments, or a nondefault port.
  public init?(link: URL) {
    guard let c = URLComponents(url: link, resolvingAgainstBaseURL: false), c.scheme == "https",
      c.host == "nara-national-archives-catalog.s3.amazonaws.com", c.port == nil || c.port == 443,
      c.user == nil, c.password == nil, c.fragment == nil
    else { return nil }
    self.init(path: c.percentEncodedPath + (c.percentEncodedQuery.map { "?" + $0 } ?? ""))
  }

  /// Creates an endpoint from an encoded bucket path.
  ///
  /// Only root listings and description/authority object paths are accepted. Dot segments,
  /// controls, encoded separators, backslashes, malformed escapes, and fragments are rejected.
  /// - Parameter path: An absolute path relative to the bucket, including its optional query.
  public init?(path: String) {
    guard path.hasPrefix("/"), !path.hasPrefix("//"), !path.contains("#"),
      path.utf8.allSatisfy({
        "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~!$&'()*+,;=:@/?%[]".utf8
          .contains($0)
      }),
      let decoded = Self.decoded(path),
      !decoded.unicodeScalars.contains(where: { $0.value < 32 || $0.value == 127 })
    else { return nil }
    let rawPath = String(
      path.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)[0])
    guard
      rawPath == "/" || rawPath.hasPrefix("/descriptions/")
        || rawPath.hasPrefix("/authority-records/")
    else { return nil }
    for segment in rawPath.split(separator: "/", omittingEmptySubsequences: false) {
      guard let value = Self.decoded(String(segment)),
        value != ".", value != "..", !value.contains("/"), !value.contains("\\")
      else { return nil }
    }
    self.path = path
  }

  package init(manifestQuery query: ManifestQuery) {
    var fields = [
      "list-type=2", "max-keys=\(query.maxKeys)", "prefix=\(Self.encoded(query.prefix))",
    ]
    if let token = query.continuationToken {
      fields.insert("continuation-token=" + Self.encoded(token), at: 0)
    }
    self = Self.builtIn("/?" + fields.joined(separator: "&"))
    manifestQuery = query
  }

  static func builtIn(_ path: String) -> Self {
    guard let value = Self(path: path) else {
      preconditionFailure("Encoded validated source inputs form valid bucket paths.")
    }
    return value
  }

  static func decoded(_ value: String) -> String? {
    let bytes = Array(value.utf8)
    var result: [UInt8] = []
    var index = 0
    while index < bytes.count {
      if bytes[index] == 37 {
        guard index + 2 < bytes.count,
          let byte = UInt8(
            String(decoding: bytes[(index + 1)...(index + 2)], as: UTF8.self), radix: 16)
        else { return nil }
        result.append(byte)
        index += 3
      } else {
        result.append(bytes[index])
        index += 1
      }
    }
    return String(validating: result, as: UTF8.self)
  }

  static func encoded(_ value: String) -> String {
    value.utf8.map { byte in
      switch byte {
      case 45, 46, 48...57, 65...90, 95, 97...122, 126: String(UnicodeScalar(byte))
      default: "%" + (byte < 16 ? "0" : "") + String(byte, radix: 16, uppercase: true)
      }
    }.joined()
  }
}

extension Endpoint where Response == BulkManifest {
  /// Describes one ListObjectsV2 request without a delimiter or local sorting.
  /// - Parameter query: The exact page selection.
  /// - Returns: An independently executable manifest endpoint.
  public static func manifest(_ query: ManifestQuery) -> Self {
    Self(manifestQuery: query)
  }
}

extension Endpoint where Response == ShardReceipt {
  /// Describes the download of one JSONL shard, optionally pinning an S3 version.
  /// - Parameter shard: A validated JSONL object reference.
  /// - Returns: A streaming download endpoint.
  public static func shard(_ shard: ShardReference) -> Self {
    builtIn(
      "/"
        + shard.key.split(separator: "/", omittingEmptySubsequences: false).map {
          encoded(String($0))
        }.joined(separator: "/")
        + (shard.versionID.map { "?versionId=" + encoded($0) } ?? ""))
  }
}
