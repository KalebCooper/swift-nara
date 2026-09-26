#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// A top-level partition family in the public NARA bulk bucket.
///
/// Each case maps to one exact storage prefix. The children of a directory are discovered by
/// listing it; no collection code or record group number is enumerated here.
/// ```swift
/// let query = try BulkDirectoryQuery(directory: .recordGroups)
/// print(query.directory.prefix)  // descriptions/record-groups/
/// ```
public enum BulkDirectory: CaseIterable, Hashable, Sendable {
  /// Authority record categories under `authority-records/`.
  case authorityRecords
  /// Collections under `descriptions/collections/`.
  case collections
  /// Record groups under `descriptions/record-groups/`.
  case recordGroups

  /// The exact storage prefix, ending in the `/` delimiter.
  public var prefix: String {
    switch self {
    case .authorityRecords: "authority-records/"
    case .collections: "descriptions/collections/"
    case .recordGroups: "descriptions/record-groups/"
    }
  }
}

extension BulkDirectory {
  /// Whether a common prefix names exactly one child: this prefix, one segment, then `/`.
  fileprivate func admitsChildPrefix(_ key: String) -> Bool {
    guard key.utf8.starts(with: prefix.utf8),
      !key.unicodeScalars.contains(where: { $0.value < 32 || $0.value == 127 || $0 == "\\" })
    else { return false }
    let segment = key.utf8.dropFirst(prefix.utf8.count)
    guard segment.last == UInt8(ascii: "/") else { return false }
    let name = segment.dropLast()
    return !name.isEmpty && !name.contains(UInt8(ascii: "/"))
      && !name.elementsEqual(".".utf8) && !name.elementsEqual("..".utf8)
  }

  /// Whether an object key sits directly in this directory, including a marker equal to it.
  fileprivate func admitsObjectKey(_ key: String) -> Bool {
    key.utf8.starts(with: prefix.utf8)
      && !key.utf8.dropFirst(prefix.utf8.count).contains(UInt8(ascii: "/"))
  }
}

/// An immutable S3 ListObjectsV2 query for one bulk directory, with the delimiter fixed to `/`.
///
/// Tokens are opaque. A completed traversal claims only the storage membership enumerated at
/// traversal time; no offset, stable snapshot, or historical completeness is implied.
/// ```swift
/// let query = try BulkDirectoryQuery(directory: .collections, maxKeys: 100)
/// ```
public struct BulkDirectoryQuery: Hashable, Sendable {
  /// The opaque token for this page, if any.
  public let continuationToken: String?
  /// The directory whose immediate children are listed.
  public let directory: BulkDirectory
  /// The maximum number of prefixes and objects together, from 1 through 1,000.
  public let maxKeys: Int

  /// Creates a directory listing query without sending a request.
  /// - Parameters:
  ///   - continuationToken: A nonempty S3 token, used unchanged.
  ///   - directory: The directory to list.
  ///   - maxKeys: A page bound; defaults to 1,000.
  /// - Throws: `ManifestError.invalidQuery` for an invalid bound or token.
  public init(continuationToken: String? = nil, directory: BulkDirectory, maxKeys: Int = 1000)
    throws(ManifestError)
  {
    guard (1...1000).contains(maxKeys),
      continuationToken.map({
        !$0.isEmpty && !$0.unicodeScalars.contains(where: { $0.value < 32 || $0.value == 127 })
      }) ?? true
    else { throw .invalidQuery }
    self.continuationToken = continuationToken
    self.directory = directory
    self.maxKeys = maxKeys
  }

  /// Validates a page and describes its continuation.
  ///
  /// A truncated page may hold prefixes and no objects. Every prefix must name one immediate
  /// child of the directory, and every object must sit directly in it; the directory's own
  /// zero-byte marker key is an object, not a child.
  /// - Parameter page: The page returned for this exact query.
  /// - Returns: The next query, or nil only for a valid terminal page.
  /// - Throws: `ManifestError.inconsistentPage` when the bucket, prefix, delimiter, bound,
  ///   token, or count differs from this query or an entry is outside the directory;
  ///   `ManifestError.missingContinuation` when a truncated page has no next token or no entries;
  ///   `ManifestError.repeatedContinuation` when the next token equals this query's token.
  public func next(after page: BulkDirectoryPage) throws(ManifestError) -> Self? {
    guard page.name == "nara-national-archives-catalog", page.prefix == directory.prefix,
      page.delimiter == "/", page.maxKeys == maxKeys, page.continuationToken == continuationToken,
      page.keyCount == page.objects.count + page.prefixes.count, page.keyCount <= maxKeys,
      page.objects.allSatisfy({ directory.admitsObjectKey($0.key) }),
      page.prefixes.allSatisfy({ directory.admitsChildPrefix($0) })
    else { throw .inconsistentPage }
    guard page.isTruncated else {
      guard page.nextContinuationToken == nil else { throw .inconsistentPage }
      return nil
    }
    guard let token = page.nextContinuationToken, !token.isEmpty, page.keyCount > 0 else {
      throw .missingContinuation
    }
    guard token != continuationToken else { throw .repeatedContinuation }
    return try Self(continuationToken: token, directory: directory, maxKeys: maxKeys)
  }
}

/// One immediate child of a bulk directory, retaining the exact discovered prefix.
///
/// The prefix is a storage path, not an identifier. It is never parsed into a NAID or a number,
/// and padding such as `rg_020/` is kept as listed.
/// ```swift
/// let partition = try BulkPartitionReference(
///   directory: .recordGroups, prefix: "descriptions/record-groups/rg_11/")
/// let shards = try ManifestQuery(prefix: partition.prefix)
/// ```
public struct BulkPartitionReference: Hashable, Sendable {
  /// The directory the prefix was discovered in.
  public let directory: BulkDirectory
  /// The exact common prefix, ending in `/`.
  public let prefix: String

  /// Creates a partition reference without sending a request.
  /// - Parameters:
  ///   - directory: The directory the prefix belongs to.
  ///   - prefix: The directory prefix followed by one nonempty segment and `/`.
  /// - Throws: `ManifestError.invalidQuery` for a prefix outside the directory, a nested or
  ///   empty segment, a `.` or `..` segment, a backslash, or a control character.
  public init(directory: BulkDirectory, prefix: String) throws(ManifestError) {
    guard directory.admitsChildPrefix(prefix) else { throw .invalidQuery }
    self.directory = directory
    self.prefix = prefix
  }
}
