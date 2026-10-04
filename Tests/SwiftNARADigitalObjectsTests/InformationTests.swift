import Foundation
import HTTPTesting
import HTTPTypes
import SwiftNARADigitalObjects
import SwiftNARADigitalObjectsModels
import SwiftNARADigitalObjectsTestSupport
import Testing

@Suite(.timeLimit(.minutes(suiteTimeLimitMinutes)))
struct InformationTests {
  @Test("Information cancellation interrupts a pending body without following links")
  func cancellation() async throws {
    let ready = AsyncStream<Void>.makeStream()
    let transport = MockTransport(answers: [
      .success(
        .init(body: {
          ready.continuation.yield(())
          return StreamedBody(AsyncStream<Data> { _ in })
        }))
    ])
    let client = try client(transport)
    let reference = try reference()
    let task = Task {
      do {
        _ = try await client.imageInformation(for: reference)
        Issue.record("Expected cancellation")
      } catch {
        guard case DigitalObjectsError.cancelled = error else { throw error }
      }
    }
    var iterator = ready.stream.makeAsyncIterator()
    _ = await iterator.next()
    task.cancel()
    try await task.value
    #expect(transport.requests.count == 1)
  }

  @Test("Information agrees across everyday request and endpoint execution")
  func equivalence() async throws {
    let bytes = try Fixture.iiifFDRInformation.data()
    let transport = MockTransport(
      answers: Array(
        repeating: .success(
          .init(
            chunks: [Data(bytes.prefix(9)), Data(bytes.dropFirst(9))],
            headers: [.contentType: "application/ld+json", .contentLength: "832"])), count: 3))
    let client = try client(transport)
    let reference = try reference()
    let request = DigitalObjectRequest.imageInformation(reference)
    #expect(transport.requests.isEmpty)
    let a = try await client.imageInformation(for: reference)
    let b = try await client.value(for: request)
    let c = try await client.send(.imageInformation(reference))
    #expect(a == b && b == c)
    #expect(a.rawBytes == bytes)
    #expect(a.status == 200 && a.retrievedAt == Date(timeIntervalSince1970: 1234))
    #expect(a.sourceURL.absoluteString.hasSuffix("/info.json"))
    #expect(transport.requests.count == 3)
    #expect(transport.requests.allSatisfy { $0.request.headerFields[.authorization] == nil })
  }

  @Test("Information bounds encoding malformed responses redirects and errors fail")
  func failures() async throws {
    let bytes = try Fixture.iiifFDRInformation.data()
    let marker = try #require(HTTPField.Name("X-Cache"))
    let answers: [MockTransport.Answer] = [
      .init(chunks: [bytes], headers: [.contentLength: "833"]),
      .init(chunks: [bytes], headers: [.contentLength: "-1"]),
      .init(chunks: [bytes], headers: [.contentEncoding: "gzip"]),
      .init(chunks: [bytes], headers: [.contentRange: "bytes 0-831/832"]),
      .init(chunks: [bytes], status: .partialContent),
      .init(chunks: [bytes], headers: [.contentType: "text/html"]),
      .init(chunks: [Data("<html/>".utf8)]),
      .init(chunks: [bytes], headers: [marker: "Error from cloudfront"]),
      .init(chunks: [], headers: [.location: "https://example.org"], status: .found),
      .init(chunks: [], status: .notFound),
    ]
    for answer in answers {
      let transport = MockTransport(answers: [.success(answer)])
      await #expect(throws: DigitalObjectsError.self) {
        try await client(transport).imageInformation(for: reference())
      }
      #expect(transport.requests.count == 1)
    }
    let transport = MockTransport(answers: [.success(.init(chunks: [bytes]))])
    await #expect(throws: DigitalObjectsError.self) {
      try await client(transport, maximumBytes: 8).imageInformation(for: reference())
    }
    let link = try #require(
      Endpoint<IIIFImageInformation>(link: reference().reference.transportURL))
    let none = MockTransport()
    await #expect(throws: DigitalObjectsError.self) { try await client(none).send(link) }
    #expect(none.requests.isEmpty)
  }

  private func client(_ transport: MockTransport, maximumBytes: Int = 1024) throws
    -> DigitalObjectsClient
  {
    DigitalObjectsClient(
      configuration: try .init(
        maximumErrorBodyBytes: 64, maximumInformationBytes: maximumBytes,
        maximumObjectBytes: 100_000, userAgent: "swift-nara tests"),
      retrievalTime: { Date(timeIntervalSince1970: 1234) }, transport: transport)
  }

  private func reference() throws -> IIIFImageReference {
    IIIFImageReference(
      reference: try DigitalObjectReference(
        naID: "122178160", objectID: "122178162",
        url:
          "https://catalog.archives.gov/medialz/presidential-libraries/roosevelt/577534/msf00611_Page_01.jpg"
      ))
  }
}
