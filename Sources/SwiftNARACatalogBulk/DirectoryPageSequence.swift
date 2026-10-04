#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

import HTTPCore
import SwiftNARACatalogBulkModels

/// Independent lazy directory listing traversals, including exact source receipts.
///
/// Invalid continuation and repeated tokens fail before the affected page is yielded. A truncated
/// page that lists only common prefixes still continues. A failure ends only that iterator. The
/// shared networking paginator owns every HTTP request.
/// ```swift
/// let query = try BulkDirectoryQuery(directory: .collections)
/// for try await page in client.directoryPages(matching: query) { print(page.value.prefixes) }
/// ```
public struct DirectoryPageSequence: AsyncSequence, Sendable {
  /// One decoded listing with its original source bytes.
  public typealias Element = SourceResponse<BulkDirectoryPage>
  /// The service's typed iteration failure.
  public typealias Failure = CatalogBulkError

  /// One exclusive traversal beginning at the original query.
  public struct Iterator: AsyncIteratorProtocol {
    /// One listing with its HTTP provenance.
    public typealias Element = SourceResponse<BulkDirectoryPage>
    /// The service's typed failure.
    public typealias Failure = CatalogBulkError

    private var base: PageSequence<DirectoryCapture>.Iterator
    private var endpoint: Endpoint<BulkDirectoryPage>
    private var finished = false
    private var query: BulkDirectoryQuery?
    private let record: (@Sendable (Element) async throws -> Void)?
    private var seen: Set<String>

    init(
      base: PageSequence<DirectoryCapture>.Iterator, endpoint: Endpoint<BulkDirectoryPage>,
      query: BulkDirectoryQuery?, record: (@Sendable (Element) async throws -> Void)?
    ) {
      self.base = base; self.endpoint = endpoint; self.query = query; self.record = record
      seen = Set(query?.continuationToken.map { [$0] } ?? [])
    }

    /// Fetches and validates one page on demand.
    /// - Returns: A valid page, or nil after terminal completion or failure.
    /// - Throws: `CatalogBulkError.cancelled` when the task is cancelled before a request or
    ///   before delivery, `CatalogBulkError.pagination` for an inconsistent page or a repeated
    ///   token, `CatalogBulkError.recording` when the recorder fails, and
    ///   `CatalogBulkError.transport` or `CatalogBulkError.decoding` for exchange failures.
    public mutating func next(isolation actor: isolated (any Actor)? = #isolation)
      async throws(CatalogBulkError) -> Element?
    {
      guard !finished else { return nil }
      finished = true
      guard !Task.isCancelled else { throw .cancelled }
      let answer: DecodedResponse<DirectoryCapture>
      do throws(TransportError) {
        guard let response = try await base.next(isolation: actor) else { return nil }
        answer = response
      } catch { throw CatalogBulkError(error) }
      var nextQuery: BulkDirectoryQuery?
      if let validation = query ?? endpoint.directoryQuery {
        do {
          let validatedNext = try validation.next(after: answer.value.page)
          nextQuery = query == nil ? nil : validatedNext
        } catch {
          throw .pagination(error)
        }
        if let token = nextQuery?.continuationToken, !seen.insert(token).inserted {
          throw .pagination(.repeatedContinuation)
        }
      }
      let result = SourceResponse(
        body: answer.value.body,
        retrieval: CatalogBulkClient.retrieval(
          headers: answer.headers, status: answer.status.code, time: answer.value.retrievedAt,
          url: endpoint.url), value: answer.value.page)
      guard !Task.isCancelled else { throw .cancelled }
      if let record {
        do { try await record(result) } catch {
          throw Task.isCancelled ? .cancelled : .recording(error)
        }
      }
      guard !Task.isCancelled else { throw .cancelled }
      if let nextQuery { endpoint = .directory(nextQuery) }
      query = nextQuery
      finished = nextQuery == nil
      return result
    }
  }

  private let base: PageSequence<DirectoryCapture>
  private let endpoint: Endpoint<BulkDirectoryPage>
  private let query: BulkDirectoryQuery?
  private let record: (@Sendable (Element) async throws -> Void)?

  init(
    base: PageSequence<DirectoryCapture>, endpoint: Endpoint<BulkDirectoryPage>,
    query: BulkDirectoryQuery?, record: (@Sendable (Element) async throws -> Void)?
  ) {
    self.base = base; self.endpoint = endpoint; self.query = query; self.record = record
  }

  /// Creates an iterator without sending a request.
  /// - Returns: A fresh independent traversal.
  public func makeAsyncIterator() -> Iterator {
    Iterator(base: base.makeAsyncIterator(), endpoint: endpoint, query: query, record: record)
  }
}
