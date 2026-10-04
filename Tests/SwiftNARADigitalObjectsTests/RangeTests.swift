import Foundation
import HTTPCore
import HTTPTesting
import HTTPTypes
import SwiftNARADigitalObjects
import SwiftNARADigitalObjectsModels
import SwiftNARADigitalObjectsTestSupport
import Testing

@Suite(.timeLimit(.minutes(suiteTimeLimitMinutes)))
struct RangeTests {
  @Test("Cancelling a pending range cleans up only its owned temporary")
  func cancellation() async throws {
    let directory = try directory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let ready = AsyncStream<Void>.makeStream()
    let transport = MockTransport(answers: [
      .success(
        .init(
          body: {
            ready.continuation.yield(())
            return StreamedBody(AsyncStream<Data> { _ in })
          }, headers: [.contentRange: "bytes 0-3/100", .eTag: "\"tag\""], status: .partialContent))
    ])
    let client = try client(transport)
    let source = try reference()
    let range = try DigitalObjectByteRange(lowerBound: 0, upperBound: 3)
    let task = Task {
      do {
        _ = try await client.downloadRange(
          range, of: source, to: directory.appendingPathComponent("range"))
        Issue.record("Expected cancellation")
      } catch {
        guard case DigitalObjectsError.cancelled = error else { throw error }
      }
    }
    var iterator = ready.stream.makeAsyncIterator()
    _ = await iterator.next()
    task.cancel()
    try await task.value
    #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
    #expect(transport.requests.count == 1)
  }

  @Test("Attributed JPEG and archival HTML fragments agree across all three range call forms")
  func captures() async throws {
    let records = try JSONDecoder().decode([Capture].self, from: Fixture.attribution.data())
    let directory = try directory()
    defer { try? FileManager.default.removeItem(at: directory) }
    for fixture in [Fixture.rangeFDRJPEG, .rangeMedialiveHTML] {
      let capture = try #require(records.first { $0.file == fixture.rawValue })
      let bytes = try fixture.data()
      var headers = HTTPFields()
      for (key, value) in capture.headers {
        headers.append(HTTPField(name: try #require(HTTPField.Name(key)), value: value))
      }
      let object = try DigitalObjectReference(
        naID: fixture == .rangeFDRJPEG ? "122178160" : "26879728",
        objectID: fixture == .rangeFDRJPEG ? "122178162" : "26879729", url: capture.url)
      let source = try DigitalObjectRangeReference(
        entityTag: #require(capture.expectedETag),
        object: object, totalByteCount: #require(capture.totalByteCount))
      let range = try DigitalObjectByteRange(lowerBound: 16, upperBound: 47)
      let request = DigitalObjectRequest.range(range, of: source)
      let transport = MockTransport(
        answers: Array(
          repeating: .success(
            .init(
              chunks: [Data(bytes.prefix(7)), Data(bytes.dropFirst(7))], headers: headers,
              status: .partialContent)), count: 4))
      let client = try client(transport)
      #expect(transport.requests.isEmpty)
      let a = try await client.downloadRange(
        range, of: source, to: directory.appendingPathComponent(fixture.rawValue + "a"))
      let b = try await client.value(
        for: request, to: directory.appendingPathComponent(fixture.rawValue + "b"))
      let c = try await client.send(
        .range(range, of: source), to: directory.appendingPathComponent(fixture.rawValue + "c"))
      let d = try await client.value(
        for: .fragment(range, source), to: directory.appendingPathComponent(fixture.rawValue + "d"))
      for receipt in [a, b, c, d] {
        #expect(receipt.byteCount == 32 && receipt.status == 206)
        #expect(receipt.transportURL.absoluteString == capture.url)
        #expect(receipt.retrievedAt == Date(timeIntervalSince1970: 1234))
        #expect(receipt.receivedRange == range && receipt.requestedRange == range)
        #expect(receipt.reference == source)
        #expect(try Data(contentsOf: receipt.fileURL) == bytes)
      }
      #expect(transport.requests.count == 4)
      #expect(
        transport.requests.allSatisfy {
          $0.request.headerFields[.range] == "bytes=16-47"
            && $0.request.headerFields[.ifMatch] == source.entityTag
            && $0.request.headerFields[.acceptEncoding] == "identity"
        })
    }
  }

  @Test("A legitimate EOF-clipped interval is preserved separately from the request")
  func clipped() async throws {
    let directory = try directory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let transport = MockTransport(answers: [
      .success(
        .init(
          chunks: [Data([1, 2, 3, 4])],
          headers: [.contentRange: "bytes 96-99/100", .eTag: "\"tag\""], status: .partialContent))
    ])
    let receipt = try await client(transport).downloadRange(
      .init(lowerBound: 96, upperBound: 120), of: reference(),
      to: directory.appendingPathComponent("range"))
    #expect(
      receipt.byteCount == 4 && receipt.requestedRange.upperBound == 120
        && receipt.receivedRange.upperBound == 99)
  }

  @Test("A destination created during transfer is preserved")
  func destinationRace() async throws {
    let directory = try directory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let destination = directory.appendingPathComponent("range")
    let transport = MockTransport()
    transport.setHandler(forPath: "/medialz/a.jpg") { _ in
      do {
        try Data("other writer".utf8).write(to: destination)
        return .success(
          .init(
            chunks: [Data([1, 2, 3, 4])],
            headers: [.contentRange: "bytes 0-3/100", .eTag: "\"tag\""], status: .partialContent))
      } catch { return .failure(.transport(kind: .other, underlying: error)) }
    }
    await #expect(throws: DigitalObjectsError.self) {
      try await client(transport).downloadRange(
        .init(lowerBound: 0, upperBound: 3),
        of: reference(), to: destination)
    }
    #expect(try Data(contentsOf: destination) == Data("other writer".utf8))
    #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path) == ["range"])
  }

  @Test("Invalid status identity range encoding and lengths never publish partial bytes")
  func failures() async throws {
    let base: HTTPFields = [.contentRange: "bytes 0-3/100", .eTag: "\"tag\""]
    var variants: [HTTPFields] = []
    for (name, values) in [
      (
        HTTPField.Name.contentRange,
        [
          "bytes 1-4/100", "bytes 0-2/100", "bytes 0-3/101", "bytes 0-3/*", "bytes +0-3/100",
          "bytes 0-3/999999999999999999999", "bytes 0-3/100, 8-9/100",
        ]
      ),
      (.eTag, ["W/\"tag\"", "\"changed\""]),
      (.contentLength, ["3", "5", "-4", "+4"]),
      (.contentEncoding, ["gzip"]),
      (.contentType, ["multipart/byteranges; boundary=x"]),
    ] {
      for value in values { var fields = base; fields[name] = value; variants.append(fields) }
    }
    var missing = base; missing[.eTag] = nil; variants.append(missing)
    missing = base; missing[.contentRange] = nil; variants.append(missing)
    let directory = try directory()
    defer { try? FileManager.default.removeItem(at: directory) }
    for headers in variants {
      let transport = MockTransport(answers: [
        .success(.init(chunks: [Data([0, 1, 2, 3])], headers: headers, status: .partialContent))
      ])
      await #expect(throws: DigitalObjectsError.self) {
        try await client(transport).downloadRange(
          .init(lowerBound: 0, upperBound: 3), of: reference(),
          to: directory.appendingPathComponent("range"))
      }
      #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
    }
    for count in [0, 3, 5] {
      let transport = MockTransport(answers: [
        .success(
          .init(chunks: [Data(repeating: 1, count: count)], headers: base, status: .partialContent))
      ])
      await #expect(throws: DigitalObjectsError.self) {
        try await client(transport).downloadRange(
          .init(lowerBound: 0, upperBound: 3), of: reference(),
          to: directory.appendingPathComponent("range"))
      }
      #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
    }
    for status in [200, 201, 302, 412, 416] {
      let transport = MockTransport(answers: [
        .success(.init(chunks: [], headers: base, status: .init(code: status)))
      ])
      do {
        _ = try await client(transport).downloadRange(
          .init(lowerBound: 0, upperBound: 3), of: reference(),
          to: directory.appendingPathComponent("range"))
        Issue.record("Expected failure")
      } catch {
        switch error {
        case DigitalObjectsError.range(.rangeNotHonored): #expect(status == 200)
        case DigitalObjectsError.range(.invalidResponse): #expect(status == 201)
        case DigitalObjectsError.transport(.httpStatus(_, let code, _)): #expect(code == status)
        default: Issue.record("Unexpected error: \(error)")
        }
      }
      #expect(transport.requests.count == 1)
      #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
    }
  }

  @Test("Local bounds invalid endpoints and existing destinations fail without transport")
  func preflight() async throws {
    let directory = try directory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let transport = MockTransport()
    let destination = directory.appendingPathComponent("range")
    for (lower, upper) in [(100, 110), (0, 100)] {
      await #expect(throws: DigitalObjectsError.self) {
        try await client(transport, maximumBytes: 4).downloadRange(
          .init(lowerBound: Int64(lower), upperBound: Int64(upper)), of: reference(),
          to: destination)
      }
    }
    let url = try #require(URL(string: "https://catalog.archives.gov/medialz/a.jpg"))
    let endpoint = try #require(Endpoint<DigitalObjectRangeReceipt>(link: url))
    await #expect(throws: DigitalObjectsError.self) {
      try await client(transport).send(endpoint, to: destination)
    }
    try FileManager.default.createSymbolicLink(
      atPath: destination.path,
      withDestinationPath: directory.appendingPathComponent("missing").path)
    await #expect(throws: DigitalObjectsError.self) {
      try await client(transport).downloadRange(
        .init(lowerBound: 0, upperBound: 3), of: reference(), to: destination)
    }
    #expect(transport.requests.isEmpty)
    #expect(
      try FileManager.default.destinationOfSymbolicLink(atPath: destination.path).hasSuffix(
        "/missing"))
    #expect(throws: DigitalObjectsError.self) {
      try DigitalObjectsConfiguration(
        maximumErrorBodyBytes: 16, maximumObjectBytes: 100, maximumRangeBytes: 0, userAgent: "tests"
      )
    }
  }

  @Test("A CloudFront error marker retains bounded evidence without publishing a fragment")
  func substitutedPage() async throws {
    let directory = try directory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let cache = try #require(HTTPField.Name("X-Cache"))
    for status in [200, 206] {
      let transport = MockTransport(answers: [
        .success(
          .init(
            chunks: [Data(repeating: 65, count: 25)],
            headers: [
              cache: "Error from cloudfront", .contentRange: "bytes 0-3/100", .eTag: "\"tag\"",
            ],
            status: .init(code: status)))
      ])
      do {
        _ = try await client(transport).downloadRange(
          .init(lowerBound: 0, upperBound: 3),
          of: reference(), to: directory.appendingPathComponent("range"))
        Issue.record("Expected error page")
      } catch {
        guard case DigitalObjectsError.errorPage(let body, let code, _, let truncated) = error
        else { throw error }
        #expect(body == Data(repeating: 65, count: 16) && code == status && truncated)
      }
      #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
    }
  }

  private struct Capture: Decodable {
    let expectedETag: String?
    let file: String
    let headers: [String: String]
    let totalByteCount: Int64?
    let url: String
  }

  private func client(_ transport: MockTransport, maximumBytes: Int64 = 64) throws
    -> DigitalObjectsClient
  {
    DigitalObjectsClient(
      configuration: try .init(
        maximumErrorBodyBytes: 16, maximumObjectBytes: 100, maximumRangeBytes: maximumBytes,
        userAgent: "swift-nara tests"),
      retrievalTime: { Date(timeIntervalSince1970: 1234) }, transport: transport)
  }

  private func directory() throws -> URL {
    let value = FileManager.default.temporaryDirectory.appendingPathComponent(
      "nara-range-tests-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: value, withIntermediateDirectories: false)
    return value
  }

  private func reference() throws -> DigitalObjectRangeReference {
    try DigitalObjectRangeReference(
      entityTag: "\"tag\"",
      object: .init(naID: "1", objectID: "2", url: "https://catalog.archives.gov/medialz/a.jpg"),
      totalByteCount: 100)
  }
}

extension DigitalObjectRequest where Response == DigitalObjectRangeReceipt {
  fileprivate static func fragment(
    _ range: DigitalObjectByteRange, _ reference: DigitalObjectRangeReference
  ) -> Self {
    Self(endpoint: .range(range, of: reference))
  }
}
