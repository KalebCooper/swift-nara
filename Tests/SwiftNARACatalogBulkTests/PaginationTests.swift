import Foundation
import HTTPTesting
import SwiftNARACatalogBulk
import SwiftNARACatalogBulkModels
import SwiftNARACatalogBulkTestSupport
import Synchronization
import Testing

@Suite(.timeLimit(.minutes(suiteTimeLimitMinutes)))
struct PaginationTests {
  @Test("Cancellation before fetching and while draining sends nothing extra")
  func cancellationBeforeFetchingAndWhileDrainingSendsNothingExtra() async throws {
    let transport = MockTransport(results: [
      .success(Response(body: try Fixture.manifestFirst.data(), status: .ok))
    ])
    let client = try makeClient(transport)
    let query = try ManifestQuery(maxKeys: 4, prefix: "descriptions/record-groups/rg_11/")
    let ready = AsyncStream<Void>.makeStream()
    let task = Task {
      var objects = client.objects(matching: query).makeAsyncIterator()
      #expect(try await objects.next() != nil)
      ready.continuation.yield(())
      var suspended = AsyncStream<Void> { _ in }.makeAsyncIterator()
      _ = await suspended.next()
      do {
        _ = try await objects.next(); Issue.record("Expected cancellation while buffered")
      } catch CatalogBulkError.cancelled {}
      #expect(try await objects.next() == nil)
      var pages = client.manifestPages(matching: query).makeAsyncIterator()
      do {
        _ = try await pages.next(); Issue.record("Expected cancellation before HTTP")
      } catch CatalogBulkError.cancelled {}
    }
    var signal = ready.stream.makeAsyncIterator()
    _ = await signal.next()
    task.cancel()
    try await task.value
    #expect(transport.requests.count == 1)
  }

  @Test("Custom endpoints have no inferred continuation")
  func customEndpointsHaveNoInferredContinuation() async throws {
    let transport = MockTransport(results: [
      .success(Response(body: try Fixture.manifestFirst.data(), status: .ok))
    ])
    let client = try makeClient(transport)
    let query = try ManifestQuery(maxKeys: 4, prefix: "descriptions/record-groups/rg_11/")
    var iterator = client.pages(for: .init(endpoint: .manifest(query))).makeAsyncIterator()
    #expect(try await iterator.next()?.value.isTruncated == true)
    #expect(try await iterator.next() == nil)
    #expect(transport.requests.count == 1)
  }

  @Test("Independent iterators and early break perform only demanded requests")
  func independentIteratorsAndEarlyBreakPerformOnlyDemandedRequests() async throws {
    let first = try Fixture.manifestFirst.data()
    let second = try Fixture.manifestSecond.data()
    let transport = MockTransport(
      results: [first, second, first].map { .success(Response(body: $0, status: .ok)) })
    let client = try makeClient(transport)
    let query = try ManifestQuery(maxKeys: 4, prefix: "descriptions/record-groups/rg_11/")
    let pages = client.manifestPages(matching: query)
    var a = pages.makeAsyncIterator()
    var b = pages.makeAsyncIterator()
    #expect(transport.requests.isEmpty)
    let firstPage = try #require(try await a.next())
    #expect(transport.requests.count == 1)
    let secondPage = try #require(try await a.next())
    #expect(firstPage.body == first)
    #expect(secondPage.body == second)
    #expect(secondPage.retrieval.url.absoluteString.contains("continuation-token="))
    #expect(secondPage.value.continuationToken == firstPage.value.nextContinuationToken)
    #expect(try await b.next()?.value == firstPage.value)
    #expect(transport.requests.count == 3)
    #expect(transport.requests[1].request.path?.contains("%2B") == true)
    let early = MockTransport(results: [.success(Response(body: first, status: .ok))])
    for try await _ in try makeClient(early).objects(matching: query) { break }
    #expect(early.requests.count == 1)
  }

  @Test("Invalid pages and later transport failures terminate the iterator")
  func invalidPagesAndLaterTransportFailuresTerminateTheIterator() async throws {
    let first = try Fixture.manifestFirst.data()
    let transport = MockTransport(results: [
      .success(Response(body: first, status: .ok)),
      .failure(.transport(kind: .connectivity, underlying: nil)),
    ])
    let query = try ManifestQuery(maxKeys: 4, prefix: "descriptions/record-groups/rg_11/")
    var pages = try makeClient(transport).manifestPages(matching: query).makeAsyncIterator()
    #expect(try await pages.next() != nil)
    await #expect(throws: CatalogBulkError.self) { try await pages.next() }
    #expect(try await pages.next() == nil)
    #expect(transport.requests.count == 2)
    let invalid = MockTransport(results: [.success(Response(body: first, status: .ok))])
    var wrong = try makeClient(invalid).manifestPages(matching: ManifestQuery()).makeAsyncIterator()
    do {
      _ = try await wrong.next(); Issue.record("Expected query mismatch")
    } catch CatalogBulkError.pagination(.inconsistentPage) {}
    #expect(try await wrong.next() == nil)
  }

  @Test("Recording sees exact bytes once and failure prevents delivery")
  func recordingSeesExactBytesOnceAndFailurePreventsDelivery() async throws {
    let data = try Fixture.manifestFirst.data()
    let transport = MockTransport(results: [.success(Response(body: data, status: .ok))])
    let calls = RecordingLog()
    let request = CatalogBulkRequest.manifest(
      try ManifestQuery(maxKeys: 4, prefix: "descriptions/record-groups/rg_11/"))
    var pages = try makeClient(transport).pages(
      for: request,
      record: { response in
        calls.append(response.body)
        throw RecorderFailure.failed
      }
    ).makeAsyncIterator()
    #expect(calls.values.isEmpty)
    do {
      _ = try await pages.next(); Issue.record("Expected recording failure")
    } catch CatalogBulkError.recording {}
    #expect(try await pages.next() == nil)
    #expect(calls.values == [data])
    #expect(transport.requests.count == 1)
  }

  @Test("Repeated cursor cycles fail before an affected page is yielded")
  func repeatedCursorCyclesFailBeforeAnAffectedPageIsYielded() async throws {
    let first = String(decoding: try Fixture.manifestFirst.data(), as: UTF8.self)
    let second = String(decoding: try Fixture.manifestSecond.data(), as: UTF8.self)
    let decoded = try BulkManifest.decode(Data(first.utf8))
    let token = try #require(decoded.nextContinuationToken)
    let next = try #require(BulkManifest.decode(Data(second.utf8)).nextContinuationToken)
    let third = second.replacingOccurrences(
      of: "<ContinuationToken>\(token)</ContinuationToken>",
      with: "<ContinuationToken>\(next)</ContinuationToken>"
    )
    .replacingOccurrences(
      of: "<NextContinuationToken>\(next)</NextContinuationToken>",
      with: "<NextContinuationToken>\(token)</NextContinuationToken>")
    let transport = MockTransport(
      results: [first, second, third].map { .success(Response(body: Data($0.utf8), status: .ok)) })
    var pages = try makeClient(transport).manifestPages(
      matching: ManifestQuery(maxKeys: 4, prefix: "descriptions/record-groups/rg_11/")
    ).makeAsyncIterator()
    #expect(try await pages.next() != nil)
    #expect(try await pages.next() != nil)
    do {
      _ = try await pages.next(); Issue.record("Expected repeated continuation")
    } catch {
      #expect(isRepeatedContinuation(error))
    }
    #expect(try await pages.next() == nil)
    #expect(transport.requests.count == 3)
  }

  @Test("Terminal page and item views contain equivalent objects")
  func terminalPageAndItemViewsContainEquivalentObjects() async throws {
    let data = try Fixture.manifestTerminal.data()
    let transport = MockTransport(
      results: Array(repeating: .success(Response(body: data, status: .ok)), count: 2))
    let client = try makeClient(transport)
    let query = try ManifestQuery(prefix: "descriptions/collections/coll_FDR-FDRMSF/")
    var pages = client.manifestPages(matching: query).makeAsyncIterator()
    let page = try #require(try await pages.next())
    #expect(try await pages.next() == nil)
    var objects: [BulkObject] = []
    for try await object in client.objects(matching: query) { objects.append(object) }
    #expect(objects == page.value.objects)
    #expect(transport.requests.count == 2)
  }
}

private func isRepeatedContinuation(_ error: any Error) -> Bool {
  guard let error = error as? CatalogBulkError else { return false }
  if case .pagination(.repeatedContinuation) = error { return true }
  return false
}

private enum RecorderFailure: Error { case failed }

private final class RecordingLog: Sendable {
  private let storage = Mutex<[Data]>([])
  var values: [Data] { storage.withLock { $0 } }
  func append(_ value: Data) { storage.withLock { $0.append(value) } }
}
