#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// One S3 ListObjectsV2 page that groups child keys into common prefixes.
///
/// Prefixes and objects are separate groups, each in provider order. An object on a directory
/// page, such as a zero-byte key equal to the listed prefix, is not a child directory. The page
/// claims only the storage membership S3 reported when it was listed. Use `BulkDirectoryCodec`
/// to read XML. Codable is for persisting the decoded value as JSON.
/// ```swift
/// let page = BulkDirectoryPage(
///   delimiter: "/", isTruncated: false, keyCount: 1, maxKeys: 20,
///   name: "nara-national-archives-catalog", objects: [], prefix: "authority-records/",
///   prefixes: ["authority-records/person/"])
/// ```
public struct BulkDirectoryPage: Codable, Hashable, Sendable, CatalogBulkResponse {
  /// The token echoed by S3, if one was requested.
  public let continuationToken: String?
  /// The delimiter echoed by S3, or nil when the listing had none.
  public let delimiter: String?
  /// Whether S3 reports more entries.
  public let isTruncated: Bool
  /// The number of prefixes and objects together reported in this page.
  public let keyCount: Int
  /// The requested page bound echoed by S3.
  public let maxKeys: Int
  /// The bucket name.
  public let name: String
  /// The next opaque token, if present.
  public let nextContinuationToken: String?
  /// Every object entry, in provider order, including a directory marker object.
  public let objects: [BulkObject]
  /// The prefix echoed by S3.
  public let prefix: String
  /// Every common prefix, in provider order, exactly as listed.
  public let prefixes: [String]

  /// Creates a page without interpreting its continuation.
  /// - Parameters:
  ///   - continuationToken: The echoed token, if one was requested.
  ///   - delimiter: The echoed delimiter, if any.
  ///   - isTruncated: Whether S3 reports more entries.
  ///   - keyCount: The reported count of prefixes and objects.
  ///   - maxKeys: The echoed page bound.
  ///   - name: The bucket name.
  ///   - nextContinuationToken: The next opaque token, if present.
  ///   - objects: The object entries in provider order.
  ///   - prefix: The echoed prefix.
  ///   - prefixes: The common prefixes in provider order.
  public init(
    continuationToken: String? = nil, delimiter: String? = nil, isTruncated: Bool, keyCount: Int,
    maxKeys: Int, name: String, nextContinuationToken: String? = nil, objects: [BulkObject],
    prefix: String, prefixes: [String]
  ) {
    self.continuationToken = continuationToken
    self.delimiter = delimiter
    self.isTruncated = isTruncated
    self.keyCount = keyCount
    self.maxKeys = maxKeys
    self.name = name
    self.nextContinuationToken = nextContinuationToken
    self.objects = objects
    self.prefix = prefix
    self.prefixes = prefixes
  }

  /// Decodes a bounded UTF-8 S3 XML directory listing.
  /// - Parameter data: The original response bytes.
  /// - Returns: The listing with its exact token, prefix order, and object order.
  /// - Throws: `CatalogDecodingError.limitExceeded` for oversized XML, or
  ///   `CatalogDecodingError.malformedXML` for invalid or inconsistent XML.
  public static func decode(_ data: Data) throws(CatalogDecodingError) -> Self {
    try BulkDirectoryCodec.decode(data)
  }
}
