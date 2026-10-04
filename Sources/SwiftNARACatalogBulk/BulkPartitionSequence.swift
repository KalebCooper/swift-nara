#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

import HTTPCore
import SwiftNARACatalogBulkModels

/// Lazy directory children that preserve provider order and duplicates across listing pages.
///
/// Objects listed directly in the directory, such as a zero-byte marker key, are not children
/// and are never yielded. A reference proves storage membership at traversal time only; its
/// prefix is not an identifier.
/// ```swift
/// let query = try BulkDirectoryQuery(directory: .recordGroups)
/// for try await partition in client.partitions(matching: query) {
///   let shards = try ManifestQuery(prefix: partition.prefix)
/// }
/// ```
public struct BulkPartitionSequence: AsyncSequence, Sendable {
  /// One immediate child of the listed directory.
  public typealias Element = BulkPartitionReference
  /// The service's typed failure.
  public typealias Failure = CatalogBulkError

  /// An exclusive traversal with at most one page of buffered prefixes.
  public struct Iterator: AsyncIteratorProtocol {
    /// One immediate child of the listed directory.
    public typealias Element = BulkPartitionReference
    /// The typed service failure.
    public typealias Failure = CatalogBulkError
    private let directory: BulkDirectory
    private var finished = false
    private var index = 0
    private var pages: DirectoryPageSequence.Iterator
    private var prefixes: [String] = []

    init(directory: BulkDirectory, pages: DirectoryPageSequence.Iterator) {
      self.directory = directory
      self.pages = pages
    }

    /// Drains the current page's prefixes before requesting the next page.
    /// - Returns: The next child reference, or nil after completion or failure.
    /// - Throws: `CatalogBulkError.cancelled` when the task is cancelled, including while
    ///   prefixes are buffered, and every failure of the underlying page traversal.
    public mutating func next(isolation actor: isolated (any Actor)? = #isolation)
      async throws(CatalogBulkError) -> BulkPartitionReference?
    {
      guard !finished else { return nil }
      finished = true
      guard !Task.isCancelled else { prefixes = []; throw .cancelled }
      while index == prefixes.count {
        guard let page = try await pages.next(isolation: actor) else { prefixes = []; return nil }
        prefixes = page.value.prefixes; index = 0
      }
      let prefix = prefixes[index]; index += 1
      let partition: BulkPartitionReference
      do { partition = try BulkPartitionReference(directory: directory, prefix: prefix) } catch {
        preconditionFailure(
          "The page traversal validated every prefix as an immediate child of this directory.")
      }
      finished = false
      return partition
    }
  }

  private let directory: BulkDirectory
  private let pages: DirectoryPageSequence

  init(directory: BulkDirectory, pages: DirectoryPageSequence) {
    self.directory = directory
    self.pages = pages
  }

  /// Creates an iterator without sending any request.
  /// - Returns: A fresh independent traversal.
  public func makeAsyncIterator() -> Iterator {
    Iterator(directory: directory, pages: pages.makeAsyncIterator())
  }
}
