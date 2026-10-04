import Foundation
import HTTPTesting
import HTTPTypes
import SwiftNARADigitalObjects
import SwiftNARADigitalObjectsModels
import SwiftNARADigitalObjectsTestSupport
import Testing

@Suite(.timeLimit(.minutes(suiteTimeLimitMinutes)))
struct ImageTests {
  @Test("Derivative cancellation removes temporary bytes and never fetches an original")
  func cancellation() async throws {
    let directory = try directory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let ready = AsyncStream<Void>.makeStream()
    let transport = MockTransport(answers: [
      .success(
        .init(body: {
          ready.continuation.yield(())
          return StreamedBody(
            AsyncStream<Data> { continuation in
              continuation.yield(Data([0xFF, 0xD8, 0xFF]))
            })
        }))
    ])
    let client = try client(transport)
    let image = try image()
    let task = Task {
      do {
        _ = try await client.downloadImage(image, to: directory.appendingPathComponent("image.jpg"))
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

  @Test("Every derivative call form saves exactly the attributed JPEG with distinct provenance")
  func equivalence() async throws {
    let directory = try directory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let bytes = try Fixture.iiifFDRWidth200.data()
    let transport = MockTransport(
      answers: Array(
        repeating: .success(
          .init(
            chunks: [
              Data(bytes.prefix(1)), Data(bytes.dropFirst(1).prefix(1)), Data(bytes.dropFirst(2)),
            ],
            headers: [.contentLength: "6031", .contentType: "image/jpeg"])), count: 4))
    let client = try client(transport)
    let image = try image()
    let request = DigitalObjectRequest.image(image)
    #expect(transport.requests.isEmpty)
    let a = try await client.downloadImage(image, to: directory.appendingPathComponent("a.jpg"))
    let b = try await client.value(for: request, to: directory.appendingPathComponent("b.jpg"))
    let c = try await client.send(.image(image), to: directory.appendingPathComponent("c.jpg"))
    let d = try await client.value(
      for: .preview(image), to: directory.appendingPathComponent("d.jpg"))
    for receipt in [a, b, c, d] {
      #expect(try Data(contentsOf: receipt.fileURL) == bytes)
      #expect(receipt.byteCount == 6031 && receipt.status == 200)
      #expect(receipt.reference.naID == "122178160" && receipt.reference.objectID == "122178162")
      #expect(receipt.request.information.rawBytes == image.information.rawBytes)
      #expect(receipt.request.size.parameter == "200,")
      #expect(
        receipt.informationID
          == "https://catalog.archives.gov/iiif/3/lz%2Fpresidential-libraries%2Froosevelt%2F577534%2Fmsf00611_Page_01.jpg"
      )
      #expect(
        receipt.transportURL.absoluteString == receipt.informationID + "/full/200,/0/default.jpg")
      #expect(receipt.mediaType == "image/jpeg")
      #expect(receipt.retrievedAt == Date(timeIntervalSince1970: 1234))
    }
    #expect(transport.requests.count == 4)
    #expect(transport.requests.allSatisfy { $0.request.headerFields[.accept] == "image/jpeg" })
    #expect(transport.requests.allSatisfy { $0.request.headerFields[.authorization] == nil })
  }

  @Test("Invalid JPEG type signature bounds and HTTP responses leave no published file")
  func failures() async throws {
    let bytes = try Fixture.iiifFDRWidth200.data()
    let marker = try #require(HTTPField.Name("X-Cache"))
    let answers: [MockTransport.Answer] = [
      .init(chunks: [bytes], headers: [.contentType: "image/png"]),
      .init(chunks: [bytes], headers: [.contentType: "application/octet-stream"]),
      .init(chunks: [Data("<html/>".utf8)]),
      .init(chunks: [Data([0xFF, 0xD8])]),
      .init(chunks: []),
      .init(chunks: [bytes], headers: [.contentLength: "6032"]),
      .init(chunks: [bytes], headers: [.contentLength: "6030"]),
      .init(chunks: [bytes], headers: [.contentEncoding: "gzip"]),
      .init(chunks: [bytes], headers: [.contentRange: "bytes 0-6030/6031"]),
      .init(chunks: [bytes], status: .partialContent),
      .init(
        chunks: [try Fixture.missingObject.data()], headers: [marker: "Error from cloudfront"]),
      .init(chunks: [], headers: [.location: "https://example.org/image.jpg"], status: .found),
      .init(chunks: [], status: .forbidden),
    ]
    let directory = try directory()
    defer { try? FileManager.default.removeItem(at: directory) }
    for answer in answers {
      let transport = MockTransport(answers: [.success(answer)])
      await #expect(throws: DigitalObjectsError.self) {
        try await client(transport).downloadImage(
          image(), to: directory.appendingPathComponent("image.jpg"))
      }
      #expect(transport.requests.count == 1)
      #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
    }
    let transport = MockTransport(answers: [.success(.init(chunks: [bytes]))])
    await #expect(throws: DigitalObjectsError.self) {
      try await client(transport, maximumBytes: 6000).downloadImage(
        image(), to: directory.appendingPathComponent("image.jpg"))
    }
    #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
    let none = MockTransport()
    let invalid = try #require(
      Endpoint<IIIFImageReceipt>(link: image().information.reference.reference.transportURL))
    await #expect(throws: DigitalObjectsError.self) {
      try await client(none).send(invalid, to: directory.appendingPathComponent("image.jpg"))
    }
    #expect(none.requests.isEmpty)
  }

  @Test("A missing image media type remains absent despite successful signature validation")
  func missingMediaType() async throws {
    let directory = try directory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let transport = MockTransport(answers: [
      .success(.init(chunks: [try Fixture.iiifFDRWidth200.data()]))
    ])
    let receipt = try await client(transport).downloadImage(
      image(), to: directory.appendingPathComponent("image.jpg"))
    #expect(receipt.mediaType == nil && receipt.byteCount == 6031)
  }

  private func client(_ transport: MockTransport, maximumBytes: Int64 = 10_000) throws
    -> DigitalObjectsClient
  {
    DigitalObjectsClient(
      configuration: try .init(
        maximumErrorBodyBytes: 64, maximumObjectBytes: maximumBytes, userAgent: "swift-nara tests"),
      retrievalTime: { Date(timeIntervalSince1970: 1234) }, transport: transport)
  }

  private func directory() throws -> URL {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      "nara-image-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
    return directory
  }

  private func image() throws -> IIIFImageRequest {
    let source = try DigitalObjectReference(
      naID: "122178160", objectID: "122178162",
      url:
        "https://catalog.archives.gov/medialz/presidential-libraries/roosevelt/577534/msf00611_Page_01.jpg"
    )
    return try IIIFImageRequest(
      information: .decode(
        Fixture.iiifFDRInformation.data(), reference: IIIFImageReference(reference: source)),
      size: .width(200))
  }
}

extension DigitalObjectRequest where Response == IIIFImageReceipt {
  fileprivate static func preview(_ image: IIIFImageRequest) -> Self {
    Self(endpoint: .image(image))
  }
}
