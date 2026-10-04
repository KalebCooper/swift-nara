import Foundation
import HTTPTesting
import HTTPTypes
import SwiftNARADigitalObjects
import SwiftNARADigitalObjectsModels
import SwiftNARADigitalObjectsTestSupport
import Testing

@Suite(.timeLimit(.minutes(suiteTimeLimitMinutes)))
struct DownloadTests {
  @Test("Cancellation before sending and while streaming leaves no file")
  func cancellation() async throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let reference = try mediaReference()
    let before = MockTransport()
    let client = try mediaClient(before)
    let cancelled = Task {
      var wait = AsyncStream<Void> { _ in }.makeAsyncIterator()
      _ = await wait.next()
      do {
        _ = try await client.download(reference, to: directory.appendingPathComponent("before"))
        Issue.record("Expected cancellation")
      } catch {
        guard case DigitalObjectsError.cancelled = error else { throw error }
      }
    }
    cancelled.cancel()
    try await cancelled.value
    #expect(before.requests.isEmpty)

    let ready = AsyncStream<Void>.makeStream()
    let transport = MockTransport(answers: [
      .success(.init(body: { StreamedBody(InterruptedMediaBody(ready: ready.continuation)) }))
    ])
    let streaming = try mediaClient(transport)
    let task = Task {
      do {
        _ = try await streaming.download(reference, to: directory.appendingPathComponent("during"))
        Issue.record("Expected cancellation")
      } catch {
        guard case DigitalObjectsError.cancelled = error else { throw error }
      }
    }
    var signal = ready.stream.makeAsyncIterator()
    _ = await signal.next()
    let files = try FileManager.default.contentsOfDirectory(
      at: directory, includingPropertiesForKeys: nil)
    #expect(files.count == 1)
    #expect(try Data(contentsOf: #require(files.first)) == Data("partial".utf8))
    task.cancel()
    try await task.value
    #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
  }

  @Test("Invalid explicit bounds and caller identities fail")
  func configuration() {
    for (errorLimit, objectLimit, identity): (Int, Int64, String) in [
      (0, 1, "app"), (1, 0, "app"), (-1, 1, "app"), (1, -1, "app"),
      (1, 1, ""), (1, 1, "  "), (1, 1, "app\r\ninjected"),
    ] {
      #expect(throws: DigitalObjectsError.self) {
        try DigitalObjectsConfiguration(
          maximumErrorBodyBytes: errorLimit, maximumObjectBytes: objectLimit, userAgent: identity)
      }
    }
  }

  @Test("Publication races preserve a destination created during transfer")
  func destinationRace() async throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let destination = directory.appendingPathComponent("out")
    let transport = MockTransport()
    transport.setHandler(forPath: try mediaReference().transportPath) { _ in
      do {
        try Data("other writer".utf8).write(to: destination)
        return .success(.init(chunks: [Data("object".utf8)]))
      } catch {
        return .failure(.transport(kind: .other, underlying: error))
      }
    }
    await #expect(throws: DigitalObjectsError.self) {
      try await mediaClient(transport).download(mediaReference(), to: destination)
    }
    #expect(try Data(contentsOf: destination) == Data("other writer".utf8))
    #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path) == ["out"])
  }

  @Test("Existing files and dangling links are refused without a request")
  func existingDestination() async throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let existing = directory.appendingPathComponent("existing")
    try Data("keep".utf8).write(to: existing)
    let dangling = directory.appendingPathComponent("dangling")
    try FileManager.default.createSymbolicLink(
      at: dangling, withDestinationURL: directory.appendingPathComponent("missing"))
    let transport = MockTransport()
    let client = try mediaClient(transport)
    for destination in [existing, dangling] {
      await #expect(throws: DigitalObjectsError.self) {
        try await client.download(mediaReference(), to: destination)
      }
    }
    #expect(try Data(contentsOf: existing) == Data("keep".utf8))
    #expect(transport.requests.isEmpty)
    #expect(
      try FileManager.default.destinationOfSymbolicLink(atPath: dangling.path).hasSuffix("/missing")
    )
  }

  @Test("HTTP status failures retain bounded evidence and never follow redirects")
  func httpFailures() async throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    for status: HTTPResponse.Status in [.found, .forbidden, .notFound, .preconditionFailed] {
      let transport = MockTransport(answers: [
        .success(
          .init(
            chunks: [Data("abcdef".utf8)], headers: [.location: "https://example.org/secret"],
            status: status))
      ])
      do {
        _ = try await mediaClient(transport, errorBytes: 3).download(
          mediaReference(), to: directory.appendingPathComponent("out"))
        Issue.record("Expected status failure")
      } catch {
        guard case DigitalObjectsError.transport(let transportError) = error,
          case .httpStatus(let body, let code, let headers) = transportError
        else { throw error }
        #expect(body == Data("abc".utf8))
        #expect(code == status.code)
        #expect(headers[.location] == "https://example.org/secret")
      }
      #expect(transport.requests.count == 1)
      #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
    }
  }

  @Test("Original JPEG bytes agree across all three call forms")
  func jpegEquivalence() async throws {
    let bytes = try Fixture.msf00611Page01.data()
    let transport = MockTransport(
      answers: Array(
        repeating: .success(
          .init(
            chunks: [Data(bytes.prefix(17)), Data(), Data(bytes.dropFirst(17))],
            headers: [.contentLength: "65981", .contentType: "image/jpeg", .eTag: "\"opaque-2\""])),
        count: 4))
    let client = try mediaClient(transport)
    let reference = try mediaReference()
    let request = DigitalObjectRequest.download(reference)
    #expect(transport.requests.isEmpty)
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let a = try await client.download(reference, to: directory.appendingPathComponent("a"))
    let b = try await client.value(for: request, to: directory.appendingPathComponent("b"))
    let c = try await client.send(.download(reference), to: directory.appendingPathComponent("c"))
    for receipt in [a, b, c] {
      #expect(try Data(contentsOf: receipt.fileURL) == bytes)
      #expect(receipt.byteCount == 65981)
      #expect(receipt.mediaType == "image/jpeg")
      #expect(receipt.reference == reference)
      #expect(receipt.status == 200)
      #expect(receipt.retrievedAt == Date(timeIntervalSince1970: 1234))
      #expect(
        receipt.transportURL.absoluteString
          == "https://catalog.archives.gov/medialz/presidential-libraries/roosevelt/577534/msf00611_Page_01.jpg"
      )
    }
    let link = try #require(Endpoint<DigitalObjectReceipt>(link: reference.transportURL))
    let custom = try await client.value(
      for: .consumerDownload(link), to: directory.appendingPathComponent("custom"))
    #expect(custom.reference == nil)
    #expect(custom.byteCount == 65981)
    #expect(transport.requests.count == 4)
    for call in transport.requests {
      #expect(call.request.headerFields[.acceptEncoding] == "identity")
      #expect(call.request.headerFields[.userAgent] == "swift-nara tests")
      #expect(call.request.headerFields[.authorization] == nil)
    }
  }

  @Test("Recorded HTML and absent-type headers allow explicitly synthetic bytes")
  func legitimateHTMLAndAbsentType() async throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    for fixture in [Fixture.htmlObjectMedialive, .htmlObjectMedialz, .medialiveNoContentType] {
      let recorded = try JSONDecoder().decode([String: String].self, from: fixture.data())
      var headers = HTTPFields()
      for (name, value) in recorded where name.lowercased() != "content-length" {
        headers.append(HTTPField(name: try #require(HTTPField.Name(name)), value: value))
      }
      // HEAD evidence has no body. These bytes and adjusted length are synthetic.
      headers[.contentLength] = "4"
      let bytes = Data("<p/>".utf8)
      let transport = MockTransport(answers: [.success(.init(chunks: [bytes], headers: headers))])
      let receipt = try await mediaClient(transport).download(
        mediaReference(), to: directory.appendingPathComponent(fixture.rawValue))
      #expect(try Data(contentsOf: receipt.fileURL) == bytes)
      if fixture == .medialiveNoContentType {
        #expect(receipt.mediaType == nil)
      } else {
        #expect(receipt.mediaType?.hasPrefix("text/html") == true)
      }
    }
  }

  @Test("Invalid whole-body responses and interrupted streams clean temporary bytes")
  func responseFailures() async throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let answers: [MockTransport.Answer] = [
      .init(
        chunks: [Data("partial".utf8)], failure: .transport(kind: .connectivity, underlying: nil)),
      .init(chunks: [Data("short".utf8)], headers: [.contentLength: "6"]),
      .init(chunks: [Data("long".utf8)], headers: [.contentLength: "3"]),
      .init(chunks: [], headers: [.contentLength: "-1"]),
      .init(chunks: [], headers: [.contentLength: "+1"]),
      .init(chunks: [], headers: [.contentLength: "9223372036854775808"]),
      .init(chunks: [], headers: [.contentLength: "11"]),
      .init(chunks: [Data(repeating: 32, count: 11)]),
      .init(chunks: [], status: .partialContent),
      .init(chunks: [], headers: [.contentRange: "bytes 0-3/4"]),
      .init(chunks: [], headers: [.contentEncoding: "gzip"]),
    ]
    for answer in answers {
      let transport = MockTransport(answers: [.success(answer)])
      await #expect(throws: DigitalObjectsError.self) {
        try await mediaClient(transport, objectBytes: 10).download(
          mediaReference(), to: directory.appendingPathComponent("out"))
      }
      #expect(transport.requests.count == 1)
      #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
    }
  }

  @Test("Both recorded error pages preserve bounded bytes and an honest truncation flag")
  func substitutedPages() async throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let field = try #require(HTTPField.Name("x-CaChE"))
    for fixture in [Fixture.missingObject, .missingMedialiveObject] {
      let bytes = try fixture.data()
      for limit in [3, 5454, 6000] {
        let transport = MockTransport(answers: [
          .success(
            .init(
              chunks: [Data(bytes.prefix(3)), Data(), Data(bytes.dropFirst(3))],
              headers: [.contentType: "image/jpeg", field: "eRrOr FrOm ClOuDfRoNt"]))
        ])
        do {
          _ = try await mediaClient(transport, errorBytes: limit).download(
            mediaReference(), to: directory.appendingPathComponent("out"))
          Issue.record("Expected substituted page")
        } catch {
          guard
            case DigitalObjectsError.errorPage(let body, let code, let headers, let truncated) =
              error
          else { throw error }
          #expect(code == 200)
          #expect(body == bytes.prefix(limit))
          #expect(truncated == (limit == 3))
          #expect(headers[.contentType] == "image/jpeg")
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
      }
    }
  }
}

private struct InterruptedMediaBody: AsyncSequence, Sendable {
  struct Iterator: AsyncIteratorProtocol {
    var first = true
    let ready: AsyncStream<Void>.Continuation

    mutating func next() async -> Data? {
      if first {
        first = false
        return Data("partial".utf8)
      }
      ready.yield(())
      var wait = AsyncStream<Data> { _ in }.makeAsyncIterator()
      return await wait.next()
    }
  }

  let ready: AsyncStream<Void>.Continuation

  func makeAsyncIterator() -> Iterator { Iterator(ready: ready) }
}

extension DigitalObjectRequest where Response == DigitalObjectReceipt {
  fileprivate static func consumerDownload(_ endpoint: Endpoint<DigitalObjectReceipt>) -> Self {
    Self(endpoint: endpoint)
  }
}

private func mediaClient(
  _ transport: MockTransport, errorBytes: Int = 1024, objectBytes: Int64 = 100_000
) throws -> DigitalObjectsClient {
  DigitalObjectsClient(
    configuration: try DigitalObjectsConfiguration(
      maximumErrorBodyBytes: errorBytes, maximumObjectBytes: objectBytes,
      userAgent: "swift-nara tests"),
    retrievalTime: { Date(timeIntervalSince1970: 1234) }, transport: transport)
}

private func mediaReference() throws -> DigitalObjectReference {
  try DigitalObjectReference(
    naID: "122178160", objectID: "122178162",
    url:
      "https://s3.amazonaws.com/NARAprodstorage/lz/presidential-libraries/roosevelt/577534/msf00611_Page_01.jpg"
  )
}

private func temporaryDirectory() throws -> URL {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
    "nara-media-test-" + UUID().uuidString)
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
  return directory
}
