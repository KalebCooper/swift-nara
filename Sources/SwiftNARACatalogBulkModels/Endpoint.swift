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
  /// The conditional validator when this endpoint was created by the refresh factory.
  public private(set) var condition: ShardCondition? = nil
  /// The exact query when this endpoint was created by the directory factory.
  public private(set) var directoryQuery: BulkDirectoryQuery? = nil
  /// The representation selected for a resumable original download, otherwise nil.
  public private(set) var downloadReference: BulkRangeReference? = nil
  /// The exact query when this endpoint was created by the manifest factory.
  public private(set) var manifestQuery: ManifestQuery? = nil
  /// The public bucket origin used by every endpoint.
  public static var origin: String { "https://nara-national-archives-catalog.s3.amazonaws.com" }
  /// The exact encoded path and query relative to the bucket origin.
  public let path: String

  /// The interval when constructed by the range factory.
  public private(set) var range: BulkByteRange? = nil
  /// The known representation when constructed by the range factory.
  public private(set) var rangeReference: BulkRangeReference? = nil

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

  package init(directoryQuery query: BulkDirectoryQuery) {
    var fields = [
      "delimiter=%2F", "list-type=2", "max-keys=\(query.maxKeys)",
      "prefix=\(Self.encoded(query.directory.prefix))",
    ]
    if let token = query.continuationToken {
      fields.insert("continuation-token=" + Self.encoded(token), at: 0)
    }
    self = Self.builtIn("/?" + fields.joined(separator: "&"))
    directoryQuery = query
  }

  private init(downloadReference: BulkRangeReference) {
    self.downloadReference = downloadReference
    path = downloadReference.path
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

  private init(range: BulkByteRange, reference: BulkRangeReference) {
    self.range = range
    self.rangeReference = reference
    path = reference.path
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

extension Endpoint where Response == BulkDirectoryPage {
  /// Describes one ListObjectsV2 request for the immediate children of a bulk directory.
  ///
  /// The query fixes the delimiter to `/`, so the page lists child prefixes and any objects
  /// directly in the directory. Fields are sent in lexical order with the token first when
  /// present; the endpoint performs no local sorting and sends nothing at construction.
  /// ```swift
  /// let endpoint = Endpoint.directory(try BulkDirectoryQuery(directory: .recordGroups))
  /// ```
  /// - Parameter query: The exact page selection.
  /// - Returns: An independently executable directory endpoint.
  public static func directory(_ query: BulkDirectoryQuery) -> Self {
    Self(directoryQuery: query)
  }
}

extension Endpoint where Response == BulkDownloadReceipt {
  /// Describes serial validated ranges without capturing a local file or performing I/O.
  /// - Parameter reference: The exact known original representation.
  /// - Returns: An independently executable resumable-download endpoint.
  public static func resumableDownload(_ reference: BulkRangeReference) -> Self {
    Self(downloadReference: reference)
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

extension Endpoint where Response == BulkRangeReceipt {
  /// Describes one interval of a known bulk representation, without construction I/O.
  /// - Parameters:
  ///   - range: Inclusive requested interval.
  ///   - reference: Key, strong validator, known total and optional version pin.
  /// - Returns: An independently executable partial-download endpoint.
  public static func range(_ range: BulkByteRange, of reference: BulkRangeReference) -> Self {
    Self(range: range, reference: reference)
  }
}

extension Endpoint where Response == ShardReceipt {
  /// Describes the download of one JSONL shard, optionally pinning an S3 version.
  /// - Parameter shard: A validated JSONL object reference.
  /// - Returns: A streaming download endpoint.
  public static func shard(_ shard: ShardReference) -> Self {
    builtIn(shardPath(shard))
  }
}

extension Endpoint where Response == ShardRefreshResult {
  /// Describes a conditional download of one JSONL shard, optionally pinning an S3 version.
  ///
  /// The path equals the ``Endpoint/shard(_:)`` path for the same reference, including any
  /// version pin, and the condition is stored as a value for the executor to send. Creating
  /// the endpoint sends nothing.
  /// ```swift
  /// let reference = try ShardReference(key: "descriptions/collections/coll_FDR-FDRMSF/coll_FDR-FDRMSF-1.jsonl")
  /// let endpoint = Endpoint.refresh(
  ///   reference, condition: try .ifNoneMatch("\"4ee6006efb1a7923711c088aaf8626a0\""))
  /// ```
  /// - Parameters:
  ///   - shard: A validated JSONL object reference.
  ///   - condition: The single validator the executor sends with the download.
  /// - Returns: A conditional streaming download endpoint.
  public static func refresh(_ shard: ShardReference, condition: ShardCondition) -> Self {
    var endpoint = builtIn(shardPath(shard))
    endpoint.condition = condition
    return endpoint
  }
}

extension Endpoint {
  /// The encoded object path for a shard, with its optional version pin.
  static func shardPath(_ shard: ShardReference) -> String {
    "/"
      + shard.key.split(separator: "/", omittingEmptySubsequences: false).map {
        encoded(String($0))
      }.joined(separator: "/")
      + (shard.versionID.map { "?versionId=" + encoded($0) } ?? "")
  }
}
