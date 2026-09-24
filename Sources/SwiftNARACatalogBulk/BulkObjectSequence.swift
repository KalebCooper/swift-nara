#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

import HTTPCore
import SwiftNARACatalogBulkModels

/// Lazy objects that preserve provider order and duplicates across manifest pages.
public struct BulkObjectSequence: AsyncSequence, Sendable {
  /// One S3 object entry.
  public typealias Element = BulkObject
  /// The service's typed failure.
  public typealias Failure = CatalogBulkError

  /// An exclusive traversal with at most one page of buffered objects.
  public struct Iterator: AsyncIteratorProtocol {
    /// One S3 object.
    public typealias Element = BulkObject
    /// The typed service failure.
    public typealias Failure = CatalogBulkError
    private var finished = false
    private var index = 0
    private var objects: [BulkObject] = []
    private var pages: ManifestPageSequence.Iterator

    init(pages: ManifestPageSequence.Iterator) { self.pages = pages }

    /// Drains the current page before requesting the next.
    /// - Returns: The next object, or nil after completion or failure.
    /// - Throws: `CatalogBulkError`, including cancellation while buffered.
    public mutating func next(isolation actor: isolated (any Actor)? = #isolation)
      async throws(CatalogBulkError) -> BulkObject?
    {
      guard !finished else { return nil }
      finished = true
      guard !Task.isCancelled else { objects = []; throw .cancelled }
      while index == objects.count {
        guard let page = try await pages.next(isolation: actor) else { objects = []; return nil }
        objects = page.value.objects; index = 0
      }
      let object = objects[index]; index += 1; finished = false
      return object
    }
  }

  private let pages: ManifestPageSequence
  init(pages: ManifestPageSequence) { self.pages = pages }
  /// Creates an iterator without sending any request.
  public func makeAsyncIterator() -> Iterator { Iterator(pages: pages.makeAsyncIterator()) }
}
