import Foundation
import HTTPTesting
import HTTPTypes
import SwiftNARACatalogBulk
import SwiftNARACatalogBulkModels
import SwiftNARACatalogBulkTestSupport
import Testing

@Suite(.timeLimit(.minutes(suiteTimeLimitMinutes)))
struct RefreshTests {
  @Test("A changed shard downloads its complete body at all three levels")
  func aChangedShardDownloadsItsCompleteBodyAtAllThreeLevels() async throws {
    let bytes = try Fixture.fdr.data()
    let answer = MockTransport.Answer(
      chunks: [Data(bytes.prefix(17)), Data(bytes.dropFirst(17))],
      headers: [.contentLength: "320707", .eTag: "\"4ee6006efb1a7923711c088aaf8626a0\""])
    let transport = MockTransport(answers: Array(repeating: .success(answer), count: 3))
    let client = try makeClient(transport)
    let reference = try ShardReference(key: fdrKey)
    // A synthetic prior entity tag that no longer matches the recorded shard.
    let condition = try ShardCondition.ifNoneMatch("\"0000000000000000000000000000beef\"")
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let a = try await client.refresh(
      reference, condition: condition, to: directory.appendingPathComponent("a.jsonl"))
    let b = try await client.value(
      for: .refresh(reference, condition: condition),
      to: directory.appendingPathComponent("b.jsonl"))
    let c = try await client.send(
      .refresh(reference, condition: condition), to: directory.appendingPathComponent("c.jsonl"))
    for result in [a, b, c] {
      guard case .downloaded(let receipt) = result else {
        Issue.record("Expected a downloaded shard"); continue
      }
      #expect(try Data(contentsOf: receipt.fileURL) == bytes)
      #expect(receipt.byteCount == 320707)
      #expect(receipt.retrieval.status == 200)
      #expect(receipt.retrieval.url.absoluteString == fdrURL)
    }
    #expect(transport.requests.count == 3)
    for call in transport.requests {
      #expect(call.request.path == "/" + fdrKey)
      #expect(call.request.headerFields[.acceptEncoding] == "identity")
      #expect(
        call.request.headerFields[values: .ifNoneMatch] == ["\"0000000000000000000000000000beef\""])
      #expect(call.request.headerFields[.ifMatch] == nil)
      let field = try #require(call.request.headerFields.first { $0.name == .ifNoneMatch })
      #expect(field.name.rawName == "If-None-Match")
      #expect(field.name.rawName == condition.fieldName)
    }
  }

  @Test("A not-modified response saves nothing and keeps its source headers")
  func aNotModifiedResponseSavesNothingAndKeepsItsSourceHeaders() async throws {
    let answer = MockTransport.Answer(
      chunks: [], headers: try notModifiedHeaders(), status: .notModified)
    let transport = MockTransport(answers: Array(repeating: .success(answer), count: 3))
    let client = try makeClient(transport)
    let reference = try ShardReference(key: fdrKey)
    let condition = try ShardCondition.ifNoneMatch("\"4ee6006efb1a7923711c088aaf8626a0\"")
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let a = try await client.refresh(
      reference, condition: condition, to: directory.appendingPathComponent("a.jsonl"))
    #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
    let b = try await client.value(
      for: .refresh(reference, condition: condition),
      to: directory.appendingPathComponent("b.jsonl"))
    #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
    let c = try await client.send(
      .refresh(reference, condition: condition), to: directory.appendingPathComponent("c.jsonl"))
    #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
    #expect(a == b && b == c)
    guard case .notModified(let retrieval) = a else {
      Issue.record("Expected a not-modified result"); return
    }
    #expect(retrieval.status == 304)
    #expect(retrieval.retrievedAt == Date(timeIntervalSince1970: 1234))
    #expect(retrieval.url.absoluteString == fdrURL)
    #expect(retrieval.headers.count == 8)
    #expect(headerValue(of: "ETag", in: retrieval) == "\"4ee6006efb1a7923711c088aaf8626a0\"")
    #expect(headerValue(of: "Last-Modified", in: retrieval) == "Thu, 09 Apr 2026 17:28:28 GMT")
    #expect(
      headerValue(of: "x-amz-version-id", in: retrieval) == "UJyiii_Crdud2H8tsuMrokVKx2zzjm.6")
    #expect(headerValue(of: "Date", in: retrieval) == "Sat, 26 Sep 2026 22:47:43 GMT")
    #expect(headerValue(of: "Content-Type", in: retrieval) == nil)
    #expect(headerValue(of: "Content-Length", in: retrieval) == nil)
    #expect(transport.requests.count == 3)
    for call in transport.requests {
      #expect(
        call.request.headerFields[values: .ifNoneMatch] == ["\"4ee6006efb1a7923711c088aaf8626a0\""])
      #expect(call.request.headerFields[.ifMatch] == nil)
    }
  }

  @Test("A failed If-Match precondition surfaces status 412 with its body and headers")
  func aFailedIfMatchPreconditionSurfacesStatus412WithItsBodyAndHeaders() async throws {
    let body = try Fixture.refreshPreconditionFailed.data()
    // The header values recorded with the fixture's 412 response.
    let answer = MockTransport.Answer(
      chunks: [body],
      headers: [
        .contentType: "application/xml", .date: "Sat, 26 Sep 2026 22:47:42 GMT",
        .server: "AmazonS3",
      ], status: .preconditionFailed)
    let transport = MockTransport(answers: [.success(answer)])
    let client = try makeClient(transport)
    let condition = try ShardCondition.ifMatch("\"0000000000000000000000000000dead\"")
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    do {
      _ = try await client.refresh(
        try ShardReference(key: fdrKey), condition: condition,
        to: directory.appendingPathComponent("out.jsonl"))
      Issue.record("Expected a precondition failure")
    } catch {
      let failure = try #require(httpStatus(error))
      #expect(failure.code == 412)
      #expect(failure.body == body)
      #expect(failure.headers[.contentType] == "application/xml")
      #expect(failure.headers[.eTag] == nil)
    }
    #expect(transport.requests.count == 1)
    let call = try #require(transport.requests.first)
    #expect(call.request.headerFields[values: .ifMatch] == ["\"0000000000000000000000000000dead\""])
    #expect(call.request.headerFields[.ifNoneMatch] == nil)
    let field = try #require(call.request.headerFields.first { $0.name == .ifMatch })
    #expect(field.name.rawName == "If-Match")
    #expect(field.name.rawName == condition.fieldName)
    #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
  }

  @Test("Forbidden and missing shards stay HTTP failures without files")
  func forbiddenAndMissingShardsStayHTTPFailuresWithoutFiles() async throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let condition = try ShardCondition.ifNoneMatch("\"4ee6006efb1a7923711c088aaf8626a0\"")
    // Synthetic S3 failures; the bodies are placeholders, not recorded responses.
    let cases: [(HTTPResponse.Status, Int, String)] = [
      (.forbidden, 403, "<Error><Code>AccessDenied</Code></Error>"),
      (.notFound, 404, "<Error><Code>NoSuchKey</Code></Error>"),
    ]
    for (status, code, text) in cases {
      let transport = MockTransport(answers: [
        .success(.init(chunks: [Data(text.utf8)], headers: [.server: "AmazonS3"], status: status))
      ])
      do {
        _ = try await makeClient(transport).refresh(
          try ShardReference(key: fdrKey), condition: condition,
          to: directory.appendingPathComponent("out.jsonl"))
        Issue.record("Expected an HTTP failure")
      } catch {
        let failure = try #require(httpStatus(error))
        #expect(failure.code == code)
        #expect(failure.body == Data(text.utf8))
        #expect(failure.headers[.server] == "AmazonS3")
      }
      #expect(transport.requests.count == 1)
      #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
    }
  }

  @Test("A same-size replacement publishes new bytes beside the untouched prior file")
  func aSameSizeReplacementPublishesNewBytesBesideTheUntouchedPriorFile() async throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let prior = directory.appendingPathComponent("prior.jsonl")
    try Data("{\"record\":{\"naId\":1}}\n".utf8).write(to: prior)
    // Synthetic replacement body with the same byte count as the prior file.
    let replacement = Data("{\"record\":{\"naId\":2}}\n".utf8)
    let transport = MockTransport(answers: [
      .success(
        .init(
          chunks: [replacement], headers: [.contentLength: "22", .eTag: "\"synthetic-2\""]))
    ])
    let client = try makeClient(transport)
    let reference = try ShardReference(key: "descriptions/test.jsonl")
    let condition = try ShardCondition.ifNoneMatch("\"synthetic-1\"")
    await #expect(throws: CatalogBulkError.self) {
      try await client.refresh(reference, condition: condition, to: prior)
    }
    #expect(transport.requests.isEmpty)
    let result = try await client.refresh(
      reference, condition: condition, to: directory.appendingPathComponent("next.jsonl"))
    guard case .downloaded(let receipt) = result else {
      Issue.record("Expected a downloaded shard"); return
    }
    #expect(receipt.byteCount == 22)
    #expect(try Data(contentsOf: receipt.fileURL) == Data("{\"record\":{\"naId\":2}}\n".utf8))
    #expect(try Data(contentsOf: prior) == Data("{\"record\":{\"naId\":1}}\n".utf8))
    #expect(
      try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted() == [
        "next.jsonl", "prior.jsonl",
      ])
    #expect(transport.requests.count == 1)
  }

  @Test("Cancellation before a refresh sends nothing and creates no file")
  func cancellationBeforeARefreshSendsNothingAndCreatesNoFile() async throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let transport = MockTransport()
    let client = try makeClient(transport)
    let reference = try ShardReference(key: "descriptions/test.jsonl")
    let condition = try ShardCondition.ifNoneMatch("\"synthetic-1\"")
    let task = Task {
      var suspended = AsyncStream<Void> { _ in }.makeAsyncIterator()
      _ = await suspended.next()
      do {
        _ = try await client.refresh(
          reference, condition: condition, to: directory.appendingPathComponent("cancelled"))
        Issue.record("Expected cancellation")
      } catch {
        #expect(isCancelled(error))
      }
    }
    task.cancel()
    await task.value
    #expect(transport.requests.isEmpty)
    #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
  }

  @Test("Cancellation during a refresh stream removes its partial file")
  func cancellationDuringARefreshStreamRemovesItsPartialFile() async throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let ready = AsyncStream<Void>.makeStream()
    let transport = MockTransport(answers: [
      .success(.init(body: { StreamedBody(InterruptedBody(ready: ready.continuation)) }))
    ])
    let client = try makeClient(transport)
    let reference = try ShardReference(key: "descriptions/test.jsonl")
    let condition = try ShardCondition.ifNoneMatch("\"synthetic-1\"")
    let task = Task {
      do {
        _ = try await client.refresh(
          reference, condition: condition, to: directory.appendingPathComponent("out.jsonl"))
        Issue.record("Expected cancellation")
      } catch {
        #expect(isCancelled(error))
      }
    }
    var signal = ready.stream.makeAsyncIterator()
    _ = await signal.next()
    let partial = try #require(
      FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).first)
    #expect(try Data(contentsOf: partial) == Data("partial".utf8))
    task.cancel()
    await task.value
    #expect(transport.requests.count == 1)
    #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
  }

  @Test("A content-encoded refresh body is refused without a file")
  func aContentEncodedRefreshBodyIsRefusedWithoutAFile() async throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let transport = MockTransport(answers: [
      .success(.init(chunks: [Data("x".utf8)], headers: [.contentEncoding: "gzip"]))
    ])
    do {
      _ = try await makeClient(transport).refresh(
        try ShardReference(key: "descriptions/test.jsonl"),
        condition: try .ifNoneMatch("\"synthetic-1\""),
        to: directory.appendingPathComponent("out.jsonl"))
      Issue.record("Expected an encoding refusal")
    } catch {
      #expect(isSizeMismatch(error))
    }
    #expect(transport.requests.count == 1)
    #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
  }

  @Test("An endpoint without a condition is sent unconditionally")
  func anEndpointWithoutAConditionIsSentUnconditionally() async throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let transport = MockTransport(answers: [
      .success(.init(chunks: [Data("{}\n".utf8)], headers: [.contentLength: "3"])),
      .success(.init(chunks: [], headers: try notModifiedHeaders(), status: .notModified)),
      .success(.init(chunks: [Data("{}\n".utf8)])),
    ])
    let client = try makeClient(transport)
    let endpoint = try #require(Endpoint<ShardRefreshResult>(path: "/descriptions/test.jsonl"))
    #expect(endpoint.condition == nil)
    let first = try await client.send(endpoint, to: directory.appendingPathComponent("a.jsonl"))
    guard case .downloaded(let receipt) = first else {
      Issue.record("Expected a downloaded shard"); return
    }
    #expect(receipt.byteCount == 3)
    let second = try await client.send(endpoint, to: directory.appendingPathComponent("b.jsonl"))
    guard case .notModified(let retrieval) = second else {
      Issue.record("Expected a not-modified result"); return
    }
    #expect(retrieval.status == 304)
    #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path) == ["a.jsonl"])
    _ = try await client.download(
      try ShardReference(key: "descriptions/test.jsonl"),
      to: directory.appendingPathComponent("c.jsonl"))
    #expect(transport.requests.count == 3)
    for call in transport.requests {
      #expect(call.request.path == "/descriptions/test.jsonl")
      #expect(call.request.headerFields[.ifMatch] == nil)
      #expect(call.request.headerFields[.ifNoneMatch] == nil)
    }
  }
}

private let fdrKey = "descriptions/collections/coll_FDR-FDRMSF/coll_FDR-FDRMSF-1.jsonl"

private let fdrURL =
  "https://nara-national-archives-catalog.s3.amazonaws.com/descriptions/collections/coll_FDR-FDRMSF/coll_FDR-FDRMSF-1.jsonl"

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

private func httpStatus(_ error: any Error) -> (body: Data, code: Int, headers: HTTPFields)? {
  guard let error = error as? CatalogBulkError,
    case .transport(.httpStatus(let body, let code, let headers)) = error
  else { return nil }
  return (body, code, headers)
}

private func isCancelled(_ error: any Error) -> Bool {
  guard let error = error as? CatalogBulkError else { return false }
  if case .cancelled = error { return true }
  return false
}

private func isSizeMismatch(_ error: any Error) -> Bool {
  guard let error = error as? CatalogBulkError else { return false }
  if case .sizeMismatch = error { return true }
  return false
}

/// The recorded 304 response headers, in name order.
private func notModifiedHeaders() throws -> HTTPFields {
  let recorded = try JSONDecoder().decode(
    [String: String].self, from: Fixture.refreshNotModified.data())
  var fields = HTTPFields()
  for (name, value) in recorded.sorted(by: { $0.key < $1.key }) {
    fields.append(HTTPField(name: try #require(HTTPField.Name(name)), value: value))
  }
  return fields
}

private func temporaryDirectory() throws -> URL {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
    "swift-nara-tests-" + UUID().uuidString)
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
  return directory
}

private func headerValue(of name: String, in retrieval: SourceRetrieval) -> String? {
  retrieval.headers.first { $0.name.lowercased() == name.lowercased() }?.value
}
