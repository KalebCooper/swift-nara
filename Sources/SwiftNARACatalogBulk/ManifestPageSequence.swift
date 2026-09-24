#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

import HTTPCore
import SwiftNARACatalogBulkModels

/// Independent lazy manifest traversals, including exact source receipts.
///
/// Invalid continuation and repeated tokens fail before the affected page is yielded. A failure
/// ends only that iterator. The shared networking paginator owns every HTTP request.
public struct ManifestPageSequence: AsyncSequence, Sendable {
  /// One decoded listing with its original source bytes.
  public typealias Element = SourceResponse<BulkManifest>
  /// The service's typed iteration failure.
  public typealias Failure = CatalogBulkError

  /// One exclusive traversal beginning at the original query.
  public struct Iterator: AsyncIteratorProtocol {
    /// One listing with its HTTP provenance.
    public typealias Element = SourceResponse<BulkManifest>
    /// The service's typed failure.
    public typealias Failure = CatalogBulkError

    private var base: PageSequence<ManifestCapture>.Iterator
    private var endpoint: Endpoint<BulkManifest>
    private var finished = false
    private var query: ManifestQuery?
    private let record: (@Sendable (Element) async throws -> Void)?
    private var seen: Set<String>

    init(
      base: PageSequence<ManifestCapture>.Iterator, endpoint: Endpoint<BulkManifest>,
      query: ManifestQuery?, record: (@Sendable (Element) async throws -> Void)?
    ) {
      self.base = base; self.endpoint = endpoint; self.query = query; self.record = record
      seen = Set(query?.continuationToken.map { [$0] } ?? [])
    }

    /// Fetches and validates one page on demand.
    /// - Returns: A valid page, or nil after terminal completion or failure.
    /// - Throws: `CatalogBulkError`, including pagination and recorder failures.
    public mutating func next(isolation actor: isolated (any Actor)? = #isolation)
      async throws(CatalogBulkError) -> Element?
    {
      guard !finished else { return nil }
      finished = true
      guard !Task.isCancelled else { throw .cancelled }
      let answer: DecodedResponse<ManifestCapture>
      do throws(TransportError) {
        guard let response = try await base.next(isolation: actor) else { return nil }
        answer = response
      } catch { throw CatalogBulkError(error) }
      var nextQuery: ManifestQuery?
      if let validation = query ?? endpoint.manifestQuery {
        do {
          let validatedNext = try validation.next(after: answer.value.manifest)
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
          url: endpoint.url), value: answer.value.manifest)
      guard !Task.isCancelled else { throw .cancelled }
      if let record {
        do { try await record(result) } catch {
          throw Task.isCancelled ? .cancelled : .recording(error)
        }
      }
      guard !Task.isCancelled else { throw .cancelled }
      if let nextQuery { endpoint = .manifest(nextQuery) }
      query = nextQuery
      finished = nextQuery == nil
      return result
    }
  }

  private let base: PageSequence<ManifestCapture>
  private let endpoint: Endpoint<BulkManifest>
  private let query: ManifestQuery?
  private let record: (@Sendable (Element) async throws -> Void)?

  init(
    base: PageSequence<ManifestCapture>, endpoint: Endpoint<BulkManifest>, query: ManifestQuery?,
    record: (@Sendable (Element) async throws -> Void)?
  ) {
    self.base = base; self.endpoint = endpoint; self.query = query; self.record = record
  }

  /// Creates an iterator without sending a request.
  /// - Returns: A fresh independent traversal.
  public func makeAsyncIterator() -> Iterator {
    Iterator(base: base.makeAsyncIterator(), endpoint: endpoint, query: query, record: record)
  }
}
