#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

import HTTPCore
import SwiftNARACatalogBulkModels

extension CatalogBulkClient {
  /// Retrieves one directory listing page through the reusable request executor.
  ///
  /// The page is validated against the query before it is returned. Its prefixes are storage
  /// paths discovered at retrieval time, not identifiers.
  /// ```swift
  /// let page = try await client.directory(matching: BulkDirectoryQuery(directory: .collections))
  /// ```
  /// - Parameter query: The page to retrieve.
  /// - Returns: The original listing envelope.
  /// - Throws: `CatalogBulkError.pagination` when the page does not answer the query,
  ///   `CatalogBulkError.decoding` for invalid XML, `CatalogBulkError.transport` for HTTP
  ///   failures, and `CatalogBulkError.cancelled` when the task is cancelled.
  public func directory(matching query: BulkDirectoryQuery) async throws(CatalogBulkError)
    -> BulkDirectoryPage
  {
    try await value(for: .directory(query))
  }

  /// Creates a lazy directory traversal with no construction I/O or prefetch.
  /// - Parameter query: The initial query.
  /// - Returns: An independently iterable page sequence, retaining source bytes and receipts.
  public func directoryPages(matching query: BulkDirectoryQuery) -> DirectoryPageSequence {
    pages(for: .directory(query))
  }

  /// Creates a lazy directory traversal with optional source recording.
  ///
  /// A recorder runs once per validated page before it is yielded. A failed recorder terminates
  /// that iterator without fetching another page. No recorder runs at sequence construction.
  /// - Parameters:
  ///   - request: The initial operation; custom endpoints yield exactly one page.
  ///   - record: An optional asynchronous persistence callback for exact bytes and provenance.
  /// - Returns: Independent, demand-driven traversals.
  public func pages(
    for request: CatalogBulkRequest<BulkDirectoryPage>,
    record: (@Sendable (SourceResponse<BulkDirectoryPage>) async throws -> Void)? = nil
  ) -> DirectoryPageSequence {
    let endpoint = Self.endpoint(for: request)
    let query: BulkDirectoryQuery?
    if case .directory(let value) = request.resolution { query = value } else { query = nil }
    let base = http.pages(
      Self.request(endpoint), as: DirectoryCapture.self,
      decode: { response in
        DirectoryCapture(
          body: response.body, page: try BulkDirectoryPage.decode(response.body),
          retrievedAt: retrievalTime())
      },
      next: { page, original in
        guard query != nil, page.value.page.isTruncated,
          let token = page.value.page.nextContinuationToken,
          let query,
          let next = try? BulkDirectoryQuery(
            continuationToken: token, directory: query.directory, maxKeys: query.maxKeys)
        else { return nil }
        return .request(Self.request(Endpoint<BulkDirectoryPage>.directory(next)))
      })
    return DirectoryPageSequence(base: base, endpoint: endpoint, query: query, record: record)
  }

  /// Creates a lazy traversal of a directory's immediate children, preserving order and duplicates.
  ///
  /// Each page's prefixes are drained before the next page is requested, and objects listed
  /// directly in the directory are not yielded. Construction sends nothing.
  /// ```swift
  /// let query = try BulkDirectoryQuery(directory: .recordGroups)
  /// for try await partition in client.partitions(matching: query) { print(partition.prefix) }
  /// ```
  /// - Parameter query: The initial query.
  /// - Returns: A lazy sequence of child references.
  public func partitions(matching query: BulkDirectoryQuery) -> BulkPartitionSequence {
    BulkPartitionSequence(directory: query.directory, pages: directoryPages(matching: query))
  }
}
