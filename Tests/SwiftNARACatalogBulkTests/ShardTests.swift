import Foundation
import HTTPTesting
import HTTPTypes
import SwiftNARACatalogBulk
import SwiftNARACatalogBulkModels
import SwiftNARACatalogBulkTestSupport
import Testing

@Suite(.timeLimit(.minutes(suiteTimeLimitMinutes)))
struct ShardTests {
  @Test("Cancellation before download publishes no file and sends no request")
  func cancellationBeforeDownloadPublishesNoFileAndSendsNoRequest() async throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let transport = MockTransport()
    let client = try makeClient(transport)
    let reference = try ShardReference(key: "descriptions/test.jsonl")
    let result = Task {
      var suspended = AsyncStream<Void> { _ in }.makeAsyncIterator()
      _ = await suspended.next()
      do {
        _ = try await client.download(reference, to: directory.appendingPathComponent("cancelled"));
        Issue.record("Expected cancellation")
      } catch CatalogBulkError.cancelled {}
    }
    result.cancel()
    try await result.value
    #expect(transport.requests.isEmpty)
    #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
  }

  @Test("Cancellation during a streamed download removes its partial file")
  func cancellationDuringDownloadRemovesItsPartialFile() async throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let ready = AsyncStream<Void>.makeStream()
    let transport = MockTransport(answers: [
      .success(
        .init(body: {
          StreamedBody(InterruptedBody(ready: ready.continuation))
        }))
    ])
    let client = try makeClient(transport)
    let reference = try ShardReference(key: "descriptions/test.jsonl")
    let task = Task {
      do {
        _ = try await client.download(reference, to: directory.appendingPathComponent("out.jsonl"))
        Issue.record("Expected cancellation")
      } catch CatalogBulkError.cancelled {}
    }
    var signal = ready.stream.makeAsyncIterator()
    _ = await signal.next()
    let partial = try #require(
      FileManager.default.contentsOfDirectory(
        at: directory,
        includingPropertiesForKeys: nil
      ).first)
    #expect(try Data(contentsOf: partial) == Data("partial".utf8))
    task.cancel()
    try await task.value
    #expect(transport.requests.count == 1)
    #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
  }

  @Test("Downloads preserve exact streamed bytes headers and version provenance")
  func downloadsPreserveExactStreamedBytesHeadersAndVersionProvenance() async throws {
    let bytes = try Fixture.fdr.data()
    let version = try #require(HTTPField.Name("x-amz-version-id"))
    let answer = MockTransport.Answer(
      chunks: [Data(bytes.prefix(17)), Data(), Data(bytes.dropFirst(17))],
      headers: [
        .contentLength: String(bytes.count), .contentType: "application/octet-stream",
        .eTag: "\"opaque-2\"", version: "version+1",
      ])
    let transport = MockTransport(answers: Array(repeating: .success(answer), count: 3))
    let client = try makeClient(transport)
    let reference = try ShardReference(
      key: "descriptions/collections/coll_FDR-FDRMSF/coll_FDR-FDRMSF-1.jsonl",
      versionID: "version+1")
    let request = CatalogBulkRequest.shard(reference)
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let a = try await client.download(reference, to: directory.appendingPathComponent("a.jsonl"))
    let b = try await client.value(for: request, to: directory.appendingPathComponent("b.jsonl"))
    let c = try await client.send(
      .shard(reference), to: directory.appendingPathComponent("c.jsonl"))
    for receipt in [a, b, c] {
      #expect(try Data(contentsOf: receipt.fileURL) == bytes)
      #expect(receipt.byteCount == 320707)
      #expect(receipt.retrieval.status == 200)
      #expect(
        receipt.retrieval.headers.contains {
          $0.name.lowercased() == "x-amz-version-id" && $0.value == "version+1"
        })
      #expect(receipt.retrieval.url.absoluteString.hasSuffix("?versionId=version%2B1"))
    }
    #expect(transport.requests.count == 3)
    var count = 0
    for try await line in try CatalogLineSequence(shard: a) { count += 1; #expect(line.shard == a) }
    #expect(count == 7)
    #expect(transport.requests.count == 3)
  }

  @Test("Incomplete oversized and refused downloads leave no partial destination")
  func incompleteOversizedAndRefusedDownloadsLeaveNoPartialDestination() async throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let reference = try ShardReference(key: "descriptions/test.jsonl")
    let answers: [MockTransport.Answer] = [
      .init(
        chunks: [Data("partial".utf8)], failure: .transport(kind: .connectivity, underlying: nil)),
      .init(chunks: [Data("short".utf8)], headers: [.contentLength: "6"]),
      .init(chunks: [Data(repeating: 32, count: 11)]),
      .init(chunks: [], status: .forbidden),
      .init(chunks: [Data("x".utf8)], status: .partialContent),
      .init(chunks: [Data("x".utf8)], headers: [.contentEncoding: "gzip"]),
    ]
    for answer in answers {
      let transport = MockTransport(answers: [.success(answer)])
      let client = try makeClient(transport, maximumShardBytes: 10)
      await #expect(throws: CatalogBulkError.self) {
        try await client.download(reference, to: directory.appendingPathComponent("out.jsonl"))
      }
      #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
    }
    let existing = directory.appendingPathComponent("existing.jsonl")
    try Data("keep".utf8).write(to: existing)
    let transport = MockTransport()
    await #expect(throws: CatalogBulkError.self) {
      try await makeClient(transport).download(reference, to: existing)
    }
    #expect(try Data(contentsOf: existing) == Data("keep".utf8))
    #expect(transport.requests.isEmpty)
  }

  @Test("Line iteration is lazy independent and preserves raw locations")
  func lineIterationIsLazyIndependentAndPreservesRawLocations() async throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("lines.jsonl")
    let first = Data("{\"record\":{\"naId\":1,\"title\":\"é\"}}\r\n".utf8)
    let second = Data("{\"record\":{\"naId\":2,\"digitalObjects\":[]}}".utf8)
    let bytes = first + second
    let receipt = try localReceipt(bytes: bytes.count, url: url)
    let lines = try CatalogLineSequence(shard: receipt)
    var a = lines.makeAsyncIterator()
    var b = lines.makeAsyncIterator()
    // The file does not exist until after both iterators have been constructed.
    try bytes.write(to: url)
    let one = try #require(try await a.next())
    let two = try #require(try await a.next())
    #expect(one.rawBytes == first && one.byteOffset == 0 && one.lineNumber == 1)
    #expect(two.rawBytes == second && two.byteOffset == Int64(first.count) && two.lineNumber == 2)
    #expect(two.record.isMetadataOnly == true)
    #expect(try await a.next() == nil)
    #expect(try await b.next()?.record.naID == "1")
  }

  @Test("Malformed blank oversized and mismatched files fail at the original location")
  func malformedBlankOversizedAndMismatchedFilesFailAtTheOriginalLocation() async throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let first = Data("{\"record\":{\"naId\":1}}\n".utf8)
    for suffix in [Data("broken\n".utf8), Data("\n".utf8), Data([0xff, 10])] {
      let url = directory.appendingPathComponent(UUID().uuidString)
      let bytes = first + suffix
      try bytes.write(to: url)
      var iterator = try CatalogLineSequence(shard: localReceipt(bytes: bytes.count, url: url))
        .makeAsyncIterator()
      #expect(try await iterator.next() != nil)
      do {
        _ = try await iterator.next(); Issue.record("Expected malformed line")
      } catch CatalogBulkError.line(let offset, let number, .malformedJSON) {
        #expect(offset == Int64(first.count) && number == 2)
      }
      #expect(try await iterator.next() == nil)
    }
    let url = directory.appendingPathComponent("oversized")
    try first.write(to: url)
    var oversized = try CatalogLineSequence(
      maximumLineBytes: 5, shard: localReceipt(bytes: first.count, url: url)
    ).makeAsyncIterator()
    do {
      _ = try await oversized.next(); Issue.record("Expected line byte bound")
    } catch CatalogBulkError.line(let offset, let number, .limitExceeded) {
      #expect(offset == 0 && number == 1)
    }
    var mismatch = try CatalogLineSequence(shard: localReceipt(bytes: first.count + 1, url: url))
      .makeAsyncIterator()
    do {
      _ = try await mismatch.next(); Issue.record("Expected file size mismatch")
    } catch CatalogBulkError.sizeMismatch {}
  }

  @Test("Record bytes crossing read boundaries and cancellation remain bounded")
  func recordBytesCrossingReadBoundariesAndCancellationRemainBounded() async throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("large.jsonl")
    let bytes = Data(
      ("{\"record\":{\"naId\":3,\"title\":\"" + String(repeating: "é", count: 40000)
        + "\"}}\n{\"record\":{\"naId\":4}}\n").utf8)
    try bytes.write(to: url)
    let lines = try CatalogLineSequence(
      maximumLineBytes: 90000, shard: localReceipt(bytes: bytes.count, url: url))
    let ready = AsyncStream<Void>.makeStream()
    let task = Task {
      var iterator = lines.makeAsyncIterator()
      #expect(try await iterator.next()?.record.title?.count == 40000)
      ready.continuation.yield(())
      var suspended = AsyncStream<Void> { _ in }.makeAsyncIterator()
      _ = await suspended.next()
      do {
        _ = try await iterator.next(); Issue.record("Expected local cancellation")
      } catch CatalogBulkError.cancelled {}
      #expect(try await iterator.next() == nil)
    }
    var signal = ready.stream.makeAsyncIterator()
    _ = await signal.next()
    task.cancel()
    try await task.value
  }
}

private struct InterruptedBody: AsyncSequence, Sendable {
  typealias Element = Data

  struct Iterator: AsyncIteratorProtocol {
    var first = true
    let ready: AsyncStream<Void>.Continuation

    mutating func next() async -> Data? {
      if first { first = false; return Data("partial".utf8) }
      ready.yield()
      var suspended = AsyncStream<Void> { _ in }.makeAsyncIterator()
      _ = await suspended.next()
      return nil
    }
  }

  let ready: AsyncStream<Void>.Continuation

  func makeAsyncIterator() -> Iterator { Iterator(ready: ready) }
}

private func localReceipt(bytes: Int, url: URL) throws -> ShardReceipt {
  ShardReceipt(
    byteCount: Int64(bytes), fileURL: url,
    retrieval: SourceRetrieval(
      headers: [], retrievedAt: Date(timeIntervalSince1970: 1234), status: 200,
      url: try #require(
        URL(
          string: "https://nara-national-archives-catalog.s3.amazonaws.com/descriptions/test.jsonl")
      )))
}

private func temporaryDirectory() throws -> URL {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
    "swift-nara-tests-" + UUID().uuidString)
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
  return directory
}
