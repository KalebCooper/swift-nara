import Foundation
import HTTPTesting
import SwiftNARACatalogBulk
import SwiftNARACatalogBulkModels
import SwiftNARACatalogBulkTestSupport
import Synchronization
import Testing

@Suite(.timeLimit(.minutes(suiteTimeLimitMinutes)))
struct DirectoryTests {
  @Test("A cancelled directory traversal sends nothing and a cancelled recorder ends it")
  func aCancelledDirectoryTraversalSendsNothingAndACancelledRecorderEndsIt() async throws {
    let transport = MockTransport(results: [
      .success(Response(body: try Fixture.directoryCollectionsFirst.data(), status: .ok))
    ])
    let client = try makeClient(transport)
    let query = try BulkDirectoryQuery(directory: .collections, maxKeys: 3)
    let ready = AsyncStream<Void>.makeStream()
    let signal = ready.continuation
    let task = Task {
      var pages = client.pages(
        for: .directory(query),
        record: { _ in
          signal.yield(())
          var suspended = AsyncStream<Void> { _ in }.makeAsyncIterator()
          _ = await suspended.next()
        }
      ).makeAsyncIterator()
      do {
        _ = try await pages.next(); Issue.record("Expected cancellation while recording")
      } catch CatalogBulkError.cancelled {}
      #expect(try await pages.next() == nil)
      var fresh = client.directoryPages(matching: query).makeAsyncIterator()
      do {
        _ = try await fresh.next(); Issue.record("Expected cancellation before HTTP")
      } catch CatalogBulkError.cancelled {}
    }
    var waiting = ready.stream.makeAsyncIterator()
    _ = await waiting.next()
    task.cancel()
    try await task.value
    #expect(transport.requests.count == 1)
  }

  @Test("Custom directory endpoints are validated and have no inferred continuation")
  func customDirectoryEndpointsAreValidatedAndHaveNoInferredContinuation() async throws {
    let data = try Fixture.directoryCollectionsFirst.data()
    let transport = MockTransport(results: [
      .success(Response(body: data, status: .ok)), .success(Response(body: data, status: .ok)),
    ])
    let client = try makeClient(transport)
    let query = try BulkDirectoryQuery(directory: .collections, maxKeys: 3)
    var iterator = client.pages(for: .init(endpoint: .directory(query))).makeAsyncIterator()
    #expect(try await iterator.next()?.value.isTruncated == true)
    #expect(try await iterator.next() == nil)
    let mismatched = try BulkDirectoryQuery(directory: .recordGroups, maxKeys: 3)
    var wrong = client.pages(for: .init(endpoint: .directory(mismatched))).makeAsyncIterator()
    do {
      _ = try await wrong.next(); Issue.record("Expected query mismatch")
    } catch CatalogBulkError.pagination(.inconsistentPage) {}
    #expect(try await wrong.next() == nil)
    #expect(transport.requests.count == 2)
  }

  @Test("Everyday, request, and endpoint directory calls return equivalent pages")
  func everydayRequestAndEndpointDirectoryCallsReturnEquivalentPages() async throws {
    let data = try Fixture.directoryCollectionsFirst.data()
    let transport = MockTransport(
      results: Array(repeating: .success(Response(body: data, status: .ok)), count: 5))
    let client = try makeClient(transport)
    let query = try BulkDirectoryQuery(directory: .collections, maxKeys: 3)
    let stored = CatalogBulkRequest.directory(query)
    let everyday = try await client.directory(matching: query)
    let reusable = try await client.value(for: stored)
    let named = try await client.value(for: .collectionsByThree())
    let endpoint = try await client.send(.directory(query))
    let receipt = try await client.response(for: .directory(query))
    #expect(everyday == reusable && reusable == named && named == endpoint)
    #expect(endpoint == receipt.value)
    #expect(receipt.body == data)
    #expect(receipt.retrieval.status == 200)
    #expect(receipt.retrieval.retrievedAt == Date(timeIntervalSince1970: 1234))
    #expect(
      everyday.prefixes == [
        "descriptions/collections/coll_1AV/", "descriptions/collections/coll_AAS/",
        "descriptions/collections/coll_AASA/",
      ])
    #expect(everyday.objects.isEmpty)
    #expect(transport.requests.count == 5)
    #expect(
      transport.requests.allSatisfy {
        $0.request.path
          == "/?delimiter=%2F&list-type=2&max-keys=3&prefix=descriptions%2Fcollections%2F"
      })
  }

  @Test("Inconsistent single directory pages fail at every request level")
  func inconsistentSingleDirectoryPagesFailAtEveryRequestLevel() async throws {
    let data = try Fixture.directoryCollectionsFirst.data()
    let transport = MockTransport(
      results: Array(repeating: .success(Response(body: data, status: .ok)), count: 3))
    let client = try makeClient(transport)
    // The collections page echoes max-keys 3, so a query for 20 cannot be answered by it.
    let query = try BulkDirectoryQuery(directory: .collections, maxKeys: 20)
    do {
      _ = try await client.directory(matching: query); Issue.record("Expected mismatch")
    } catch CatalogBulkError.pagination(.inconsistentPage) {}
    do {
      _ = try await client.value(for: .directory(query)); Issue.record("Expected mismatch")
    } catch CatalogBulkError.pagination(.inconsistentPage) {}
    do {
      _ = try await client.send(.directory(query)); Issue.record("Expected mismatch")
    } catch CatalogBulkError.pagination(.inconsistentPage) {}
    #expect(transport.requests.count == 3)
  }

  @Test("Independent directory iterators and early break perform only demanded requests")
  func independentDirectoryIteratorsAndEarlyBreakPerformOnlyDemandedRequests() async throws {
    let first = try Fixture.directoryCollectionsFirst.data()
    let second = try Fixture.directoryCollectionsSecond.data()
    let transport = MockTransport(
      results: [first, second, first].map { .success(Response(body: $0, status: .ok)) })
    let client = try makeClient(transport)
    let query = try BulkDirectoryQuery(directory: .collections, maxKeys: 3)
    let pages = client.directoryPages(matching: query)
    var a = pages.makeAsyncIterator()
    var b = pages.makeAsyncIterator()
    #expect(transport.requests.isEmpty)
    let firstPage = try #require(try await a.next())
    #expect(transport.requests.count == 1)
    let secondPage = try #require(try await a.next())
    #expect(firstPage.body == first)
    #expect(secondPage.body == second)
    #expect(try await b.next()?.body == first)
    #expect(transport.requests.count == 3)
    let early = MockTransport(results: [.success(Response(body: first, status: .ok))])
    for try await _ in try makeClient(early).directoryPages(matching: query) { break }
    #expect(early.requests.count == 1)
  }

  @Test("A later transport failure ends only the affected directory iterator")
  func aLaterTransportFailureEndsOnlyTheAffectedDirectoryIterator() async throws {
    let first = try Fixture.directoryCollectionsFirst.data()
    let transport = MockTransport(results: [
      .success(Response(body: first, status: .ok)),
      .failure(.transport(kind: .connectivity, underlying: nil)),
      .success(Response(body: first, status: .ok)),
    ])
    let query = try BulkDirectoryQuery(directory: .collections, maxKeys: 3)
    let pages = try makeClient(transport).directoryPages(matching: query)
    var failing = pages.makeAsyncIterator()
    #expect(try await failing.next()?.body == first)
    do {
      _ = try await failing.next(); Issue.record("Expected a transport failure")
    } catch CatalogBulkError.transport {}
    #expect(try await failing.next() == nil)
    var other = pages.makeAsyncIterator()
    #expect(try await other.next()?.body == first)
    #expect(transport.requests.count == 3)
  }

  @Test("A prefix-only truncated directory page progresses with its exact token")
  func aPrefixOnlyTruncatedDirectoryPageProgressesWithItsExactToken() async throws {
    let first = try Fixture.directoryCollectionsFirst.data()
    let second = try Fixture.directoryCollectionsSecond.data()
    let query = try BulkDirectoryQuery(directory: .collections, maxKeys: 3)
    for useRequest in [false, true] {
      let transport = MockTransport(
        results: [first, second].map { .success(Response(body: $0, status: .ok)) })
      let client = try makeClient(transport)
      let pages =
        useRequest ? client.pages(for: .directory(query)) : client.directoryPages(matching: query)
      var iterator = pages.makeAsyncIterator()
      let firstPage = try #require(try await iterator.next())
      let secondPage = try #require(try await iterator.next())
      #expect(firstPage.value.objects.isEmpty && firstPage.value.isTruncated)
      #expect(firstPage.body == first)
      #expect(secondPage.body == second)
      #expect(secondPage.value.continuationToken == collectionsFirstNextToken)
      #expect(
        secondPage.value.prefixes == [
          "descriptions/collections/coll_AAW/", "descriptions/collections/coll_ABC/",
          "descriptions/collections/coll_ABDIL/",
        ])
      #expect(
        secondPage.retrieval.url.absoluteString
          == "https://nara-national-archives-catalog.s3.amazonaws.com/?continuation-token="
          + "1vKoy990xdAaYk7IeulTw7YN3lqzxgzJUobs6jaPU768AB6%2FvlB7TQLVrLOZ6Lxs44%2BgY0H59tiSXR70"
          + "41G3%2B0Zw754okniFAsEavEOa0D2I%3D&delimiter=%2F&list-type=2&max-keys=3"
          + "&prefix=descriptions%2Fcollections%2F")
      #expect(transport.requests.count == 2)
    }
  }

  @Test("A repeated directory token fails before the affected page is yielded")
  func aRepeatedDirectoryTokenFailsBeforeTheAffectedPageIsYielded() async throws {
    let first = String(decoding: try Fixture.directoryCollectionsFirst.data(), as: UTF8.self)
    let second = String(decoding: try Fixture.directoryCollectionsSecond.data(), as: UTF8.self)
    // Synthetic third page: it answers the second token and points back to the first token.
    let third = second.replacingOccurrences(
      of: "<ContinuationToken>\(collectionsFirstNextToken)</ContinuationToken>",
      with: "<ContinuationToken>\(collectionsSecondNextToken)</ContinuationToken>"
    )
    .replacingOccurrences(
      of: "<NextContinuationToken>\(collectionsSecondNextToken)</NextContinuationToken>",
      with: "<NextContinuationToken>\(collectionsFirstNextToken)</NextContinuationToken>")
    #expect(third != second)
    let transport = MockTransport(
      results: [first, second, third].map { .success(Response(body: Data($0.utf8), status: .ok)) })
    let delivered = DeliveredBodies()
    var pages = try makeClient(transport).pages(
      for: .directory(BulkDirectoryQuery(directory: .collections, maxKeys: 3)),
      record: { delivered.append($0.body) }
    ).makeAsyncIterator()
    #expect(try await pages.next() != nil)
    #expect(try await pages.next() != nil)
    do {
      _ = try await pages.next(); Issue.record("Expected repeated continuation")
    } catch {
      #expect(isRepeatedContinuation(error))
    }
    #expect(try await pages.next() == nil)
    #expect(delivered.values == [Data(first.utf8), Data(second.utf8)])
    #expect(transport.requests.count == 3)
  }

  @Test("Record group partitions drain in listed order before the next page is requested")
  func recordGroupPartitionsDrainInListedOrderBeforeTheNextPageIsRequested() async throws {
    let transport = MockTransport(results: [
      .success(Response(body: try Fixture.directoryRecordGroups.data(), status: .ok)),
      .failure(.transport(kind: .connectivity, underlying: nil)),
    ])
    let query = try BulkDirectoryQuery(directory: .recordGroups, maxKeys: 3)
    var partitions = try makeClient(transport).partitions(matching: query).makeAsyncIterator()
    #expect(transport.requests.isEmpty)
    var listed: [BulkPartitionReference] = []
    for _ in 0..<3 { listed.append(try #require(try await partitions.next())) }
    #expect(
      listed.map(\.prefix) == [
        "descriptions/record-groups/rg_1/", "descriptions/record-groups/rg_10/",
        "descriptions/record-groups/rg_100/",
      ])
    #expect(listed.allSatisfy { $0.directory == .recordGroups })
    let shards = try listed.map { try ManifestQuery(prefix: $0.prefix) }
    #expect(shards.map(\.prefix) == listed.map(\.prefix))
    #expect(transport.requests.count == 1)
    do {
      _ = try await partitions.next(); Issue.record("Expected a transport failure")
    } catch {
      #expect(isTransportFailure(error))
    }
    #expect(try await partitions.next() == nil)
    #expect(transport.requests.count == 2)
    #expect(
      transport.requests[1].request.path
        == "/?continuation-token=1Bosm1TzvfhXnQ%2FbUBDteAJnLrhWquwvcQB4LCb68zQL6kf41OplPJMIQT%2F"
        + "sSYUvjX6tve8edu0tBtCXgM9ZWxpaW9NOj6VpsSJWwOA9SLmQ%3D&delimiter=%2F&list-type=2"
        + "&max-keys=3&prefix=descriptions%2Frecord-groups%2F")
  }

  @Test("Directory marker objects are never yielded as partitions")
  func directoryMarkerObjectsAreNeverYieldedAsPartitions() async throws {
    let transport = MockTransport(results: [
      .success(Response(body: try Fixture.directoryAuthorityRecords.data(), status: .ok))
    ])
    let query = try BulkDirectoryQuery(directory: .authorityRecords, maxKeys: 20)
    var prefixes: [String] = []
    for try await partition in try makeClient(transport).partitions(matching: query) {
      prefixes.append(partition.prefix)
    }
    #expect(
      prefixes == [
        "authority-records/geographic-reference/", "authority-records/organization/",
        "authority-records/person/", "authority-records/specific-records-type/",
        "authority-records/topical-subject/",
      ])
    #expect(transport.requests.count == 1)
  }

  @Test("Duplicate partition prefixes are yielded as listed")
  func duplicatePartitionPrefixesAreYieldedAsListed() async throws {
    let listing = String(decoding: try Fixture.directoryRecordGroups.data(), as: UTF8.self)
    // Synthetic page: the second listed prefix repeats the first.
    let duplicated = listing.replacingOccurrences(
      of: "<Prefix>descriptions/record-groups/rg_10/</Prefix>",
      with: "<Prefix>descriptions/record-groups/rg_1/</Prefix>")
    #expect(duplicated != listing)
    let transport = MockTransport(results: [
      .success(Response(body: Data(duplicated.utf8), status: .ok))
    ])
    let query = try BulkDirectoryQuery(directory: .recordGroups, maxKeys: 3)
    var partitions = try makeClient(transport).partitions(matching: query).makeAsyncIterator()
    var prefixes: [String] = []
    for _ in 0..<3 { prefixes.append(try #require(try await partitions.next()).prefix) }
    #expect(
      prefixes == [
        "descriptions/record-groups/rg_1/", "descriptions/record-groups/rg_1/",
        "descriptions/record-groups/rg_100/",
      ])
    #expect(transport.requests.count == 1)
  }

  @Test("Early break and cancellation while draining partitions send no further request")
  func earlyBreakAndCancellationWhileDrainingPartitionsSendNoFurtherRequest() async throws {
    let data = try Fixture.directoryRecordGroups.data()
    let query = try BulkDirectoryQuery(directory: .recordGroups, maxKeys: 3)
    let early = MockTransport(results: [.success(Response(body: data, status: .ok))])
    for try await _ in try makeClient(early).partitions(matching: query) { break }
    #expect(early.requests.count == 1)
    let transport = MockTransport(results: [.success(Response(body: data, status: .ok))])
    let client = try makeClient(transport)
    let ready = AsyncStream<Void>.makeStream()
    let task = Task {
      var partitions = client.partitions(matching: query).makeAsyncIterator()
      #expect(try await partitions.next()?.prefix == "descriptions/record-groups/rg_1/")
      ready.continuation.yield(())
      var suspended = AsyncStream<Void> { _ in }.makeAsyncIterator()
      _ = await suspended.next()
      do {
        _ = try await partitions.next(); Issue.record("Expected cancellation while buffered")
      } catch CatalogBulkError.cancelled {}
      #expect(try await partitions.next() == nil)
    }
    var signal = ready.stream.makeAsyncIterator()
    _ = await signal.next()
    task.cancel()
    try await task.value
    #expect(transport.requests.count == 1)
  }
}

private let collectionsFirstNextToken =
  "1vKoy990xdAaYk7IeulTw7YN3lqzxgzJUobs6jaPU768AB6/vlB7TQLVrLOZ6Lxs44+gY0H59tiSXR7041G3+0Zw754okniFAsEavEOa0D2I="

private let collectionsSecondNextToken =
  "1bjNCKdEexoAtW5wz12Lrll5qy8q92/HGB/ExFLhOJFqZS16k+WXQKYW9NKIkG98L9kHdUO+kfTGHCVAcW1cEXsOWso29XGtWqaGoaLz8FtY="

private final class DeliveredBodies: Sendable {
  private let storage = Mutex<[Data]>([])
  var values: [Data] { storage.withLock { $0 } }
  func append(_ value: Data) { storage.withLock { $0.append(value) } }
}

private func isRepeatedContinuation(_ error: any Error) -> Bool {
  guard let error = error as? CatalogBulkError else { return false }
  if case .pagination(.repeatedContinuation) = error { return true }
  return false
}

private func isTransportFailure(_ error: any Error) -> Bool {
  guard let error = error as? CatalogBulkError else { return false }
  if case .transport = error { return true }
  return false
}

extension CatalogBulkRequest where Response == BulkDirectoryPage {
  fileprivate static func collectionsByThree() throws -> Self {
    .directory(try BulkDirectoryQuery(directory: .collections, maxKeys: 3))
  }
}
