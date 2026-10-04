import Foundation
import HTTPCore
import HTTPTesting
import HTTPTypes
import SwiftNARACatalogBulk
import SwiftNARACatalogBulkModels
import SwiftNARACatalogBulkTestSupport
import Testing

@Suite(.timeLimit(.minutes(suiteTimeLimitMinutes)))
struct ArchiveDownloadTests {
  @Test("Archive byte and workspace budgets are explicit and reject before publication")
  func bounds() async throws {
    #expect(throws: CatalogBulkError.self) {
      try BulkArchiveDownloadLimits(maximumByteCount: 0, maximumWorkspaceBytes: 1)
    }
    #expect(throws: CatalogBulkError.self) {
      try BulkArchiveDownloadLimits(maximumByteCount: 1, maximumWorkspaceBytes: 0)
    }
    let directory = try directory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let bytes = try Fixture.syntheticArchive.data()
    for variant in 0..<3 {
      let transport = MockTransport(answers: [
        .success(
          .init(
            chunks: [bytes],
            headers: variant == 0 ? [.contentLength: "229"] : [:]))
      ])
      let limits = try BulkArchiveDownloadLimits(
        maximumByteCount: variant == 2 ? 1_000 : 228,
        maximumWorkspaceBytes: variant == 2 ? 228 : 1_000)
      let failed = try await failure {
        _ = try await client(transport).downloadArchive(
          reference(), to: directory.appendingPathComponent("out"), limits: limits)
      }
      guard case .limitExceeded = failed else { Issue.record("Expected explicit bound"); continue }
      #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
    }
    let transport = MockTransport()
    let archiveClient = try client(transport)
    let range = try reference().rangeReference(entityTag: "\"tag\"", totalByteCount: 229)
    for limits in [
      try BulkArchiveDownloadLimits(maximumByteCount: 228, maximumWorkspaceBytes: 3_000_000),
      try BulkArchiveDownloadLimits(maximumByteCount: 229, maximumWorkspaceBytes: 229),
      try BulkArchiveDownloadLimits(maximumByteCount: .max, maximumWorkspaceBytes: .max),
    ] {
      let selected =
        limits.maximumByteCount == .max
        ? try reference().rangeReference(entityTag: "\"tag\"", totalByteCount: .max) : range
      #expect(throws: CatalogBulkError.self) {
        try archiveClient.beginArchiveDownload(selected, in: directory, limits: limits)
      }
    }
    #expect(transport.requests.isEmpty)
    #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
  }

  @Test("Cancellation while an archive body is pending removes only owned temporary bytes")
  func cancellation() async throws {
    let directory = try directory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let ready = AsyncStream<Void>.makeStream()
    let transport = MockTransport(answers: [
      .success(
        .init(body: {
          ready.continuation.yield(())
          return StreamedBody(AsyncStream<Data> { $0.yield(Data("PK".utf8)) })
        }))
    ])
    let client = try client(transport)
    let source = try reference()
    let limits = try limits()
    let task = Task {
      try await failure {
        _ = try await client.downloadArchive(
          source, to: directory.appendingPathComponent("out"), limits: limits)
      }
    }
    var iterator = ready.stream.makeAsyncIterator()
    _ = await iterator.next()
    task.cancel()
    let error = try await task.value
    guard case .cancelled = error else { Issue.record("Expected cancellation"); return }
    #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
  }

  @Test("Archive acquisition refuses existing destinations and a publication race")
  func destinations() async throws {
    let directory = try directory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let destination = directory.appendingPathComponent("out")
    let bytes = try Fixture.syntheticArchive.data()
    let source = try reference()
    let transport = MockTransport()
    let client = try client(transport)
    try Data("keep".utf8).write(to: destination)
    _ = try await failure {
      _ = try await client.downloadArchive(source, to: destination, limits: limits())
    }
    #expect(transport.requests.isEmpty)
    #expect(try Data(contentsOf: destination) == Data("keep".utf8))
    try FileManager.default.removeItem(at: destination)
    try FileManager.default.createSymbolicLink(
      at: destination, withDestinationURL: directory.appendingPathComponent("absent"))
    _ = try await failure {
      _ = try await client.downloadArchive(source, to: destination, limits: limits())
    }
    #expect(transport.requests.isEmpty)
    try FileManager.default.removeItem(at: destination)
    transport.setHandler(forPath: source.path) { _ in
      do {
        try Data("winner".utf8).write(to: destination)
        return .success(.init(chunks: [bytes]))
      } catch { return .failure(.transport(kind: .other, underlying: error)) }
    }
    _ = try await failure {
      _ = try await client.downloadArchive(source, to: destination, limits: limits())
    }
    #expect(try Data(contentsOf: destination) == Data("winner".utf8))
    #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path) == ["out"])
  }

  @Test("Every archive acquisition call form preserves complete fixture bytes and SHA-256")
  func equivalence() async throws {
    let directory = try directory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let bytes = try Fixture.syntheticArchive.data()
    let source = try reference()
    let transport = MockTransport(
      answers: (0..<4).map { _ in
        .success(
          .init(chunks: [bytes.prefix(7), bytes.dropFirst(7)], headers: [.contentLength: "229"]))
      })
    let client = try client(transport)
    let request = CatalogBulkRequest.archive(source)
    #expect(transport.requests.isEmpty)
    for form in 0..<4 {
      let destination = directory.appendingPathComponent("out-\(form)")
      let receipt: BulkArchiveReceipt
      switch form {
      case 0: receipt = try await client.downloadArchive(source, to: destination, limits: limits())
      case 1: receipt = try await client.value(for: request, to: destination, limits: limits())
      case 2: receipt = try await client.send(.archive(source), to: destination, limits: limits())
      default:
        receipt = try await client.value(
          for: .selectedArchive(source), to: destination, limits: limits())
      }
      #expect(
        try JSONDecoder().decode(BulkArchiveReceipt.self, from: JSONEncoder().encode(receipt))
          == receipt)
      #expect(receipt.byteCount == 229)
      #expect(receipt.checkpoint == nil)
      #expect(receipt.reference == source)
      #expect(receipt.retrieval.status == 200)
      #expect(receipt.retrieval.retrievedAt == Date(timeIntervalSince1970: 1234))
      #expect(receipt.sha256 == "93b9503f61b3b89fd29a3de15c6309be948c4c34af22bb42fb61d32d79214da9")
      #expect(try Data(contentsOf: destination) == bytes)
    }
    #expect(transport.requests.count == 4)
    #expect(
      transport.requests.allSatisfy { $0.request.headerFields[.acceptEncoding] == "identity" })
  }

  @Test(
    "Partial responses encodings incomplete lengths and empty bodies never produce archive receipts"
  )
  func invalidResponses() async throws {
    let directory = try directory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let bytes = try Fixture.syntheticArchive.data()
    for variant in 0..<7 {
      var fields: HTTPFields = [:]
      switch variant {
      case 1: fields[.contentRange] = "bytes 0-228/229"
      case 2: fields[.contentEncoding] = "gzip"
      case 3: fields[.contentLength] = "230"
      case 4: fields[.contentLength] = "-1"
      case 5: fields[.contentLength] = "229x"
      default: break
      }
      let transport = MockTransport(answers: [
        .success(
          .init(
            chunks: variant == 6 ? [] : [bytes], headers: fields,
            status: variant == 0 ? .partialContent : .ok))
      ])
      let failed = try await failure {
        _ = try await client(transport).downloadArchive(
          reference(), to: directory.appendingPathComponent("out"), limits: limits())
      }
      guard case .sizeMismatch = failed else {
        Issue.record("Expected complete representation failure"); continue
      }
      #expect(transport.requests.count == 1)
      #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
    }
  }

  @Test("Archive resume preserves identity digest final-range evidence and explicit owned state")
  func resumeEquivalence() async throws {
    let directory = try directory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let bytes = try Fixture.syntheticArchive.data()
    let source = try reference()
    for form in 0..<4 {
      let transport = MockTransport()
      transport.setHandler(forPath: source.path) { request in
        let parts = request.headerFields[.range]?.dropFirst(6).split(separator: "-") ?? []
        guard parts.count == 2, let lower = Int(parts[0]), let upper = Int(parts[1]),
          lower >= 0, upper < bytes.count, upper >= lower
        else { return .failure(.cancelled) }
        return .success(
          .init(
            chunks: [bytes.subdata(in: lower..<(upper + 1))],
            headers: [.contentRange: "bytes \(lower)-\(upper)/229", .eTag: "\"tag\""],
            status: .partialContent))
      }
      let client = try client(transport)
      let checkpoint = try client.beginArchiveDownload(
        source.rangeReference(entityTag: "\"tag\"", totalByteCount: 229),
        in: directory, limits: limits())
      #expect(transport.requests.isEmpty)
      let destination = directory.appendingPathComponent("resumed-\(form)")
      let receipt: BulkArchiveReceipt
      switch form {
      case 0:
        receipt = try await client.resumeArchiveDownload(
          checkpoint, to: destination, limits: limits())
      case 1:
        receipt = try await client.value(
          for: .archive(source), checkpoint: checkpoint, to: destination, limits: limits())
      case 2:
        receipt = try await client.send(
          .archive(source), checkpoint: checkpoint, to: destination, limits: limits())
      default:
        receipt = try await client.value(
          for: .selectedArchive(source), checkpoint: checkpoint, to: destination, limits: limits())
      }
      #expect(receipt.byteCount == 229)
      #expect(
        try JSONDecoder().decode(BulkArchiveReceipt.self, from: JSONEncoder().encode(receipt))
          == receipt)
      #expect(receipt.checkpoint?.committedByteCount == 229)
      #expect(receipt.retrieval.status == 206)
      #expect(
        receipt.retrieval.headers.contains {
          $0.name.lowercased() == "content-range" && $0.value == "bytes 192-228/229"
        })
      #expect(receipt.sha256 == "93b9503f61b3b89fd29a3de15c6309be948c4c34af22bb42fb61d32d79214da9")
      #expect(try Data(contentsOf: destination) == bytes)
      #expect(transport.requests.count == 4)
      try client.discardDownload(checkpoint)
      #expect(try Data(contentsOf: destination) == bytes)
    }
  }

  @Test("Selected archive versions require matching response evidence")
  func versions() async throws {
    let directory = try directory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let source = try BulkArchiveReference(key: "zip/export space%.zip", versionID: "a+/=")
    #expect(source.path == "/zip/export%20space%25.zip?versionId=a%2B%2F%3D")
    let name = try #require(HTTPField.Name("x-amz-version-id"))
    let bytes = try Fixture.syntheticArchive.data()
    for version in [nil, "changed", "a+/="] {
      var fields: HTTPFields = [:]
      fields[name] = version
      let transport = MockTransport(answers: [.success(.init(chunks: [bytes], headers: fields))])
      let client = try client(transport)
      let destination = directory.appendingPathComponent("out")
      if version == "a+/=" {
        let receipt = try await client.downloadArchive(source, to: destination, limits: limits())
        #expect(receipt.reference.versionID == "a+/=")
        #expect(
          receipt.retrieval.url.absoluteString
            == "https://nara-national-archives-catalog.s3.amazonaws.com/zip/export%20space%25.zip?versionId=a%2B%2F%3D"
        )
      } else {
        let error = try await failure {
          _ = try await client.downloadArchive(source, to: destination, limits: limits())
        }
        guard case .range(.representationChanged) = error else {
          Issue.record("Expected version refusal"); continue
        }
      }
    }
  }

  private func client(_ transport: MockTransport) throws -> CatalogBulkClient {
    CatalogBulkClient(
      configuration: try .init(maximumRangeBytes: 64, userAgent: "swift-nara tests"),
      retrievalTime: { Date(timeIntervalSince1970: 1234) }, transport: transport)
  }

  private func directory() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
    return url
  }

  private func failure(_ operation: () async throws -> Void) async throws -> CatalogBulkError {
    do { try await operation() } catch let error as CatalogBulkError { return error }
    throw CocoaError(.fileReadCorruptFile)
  }

  private func limits() throws -> BulkArchiveDownloadLimits {
    try BulkArchiveDownloadLimits(maximumByteCount: 1_000, maximumWorkspaceBytes: 3_000_000)
  }

  private func reference() throws -> BulkArchiveReference {
    try BulkArchiveReference(key: "zip/example.zip")
  }
}

extension CatalogBulkRequest where Response == BulkArchiveReceipt {
  fileprivate static func selectedArchive(_ reference: BulkArchiveReference) -> Self {
    Self(endpoint: .archive(reference))
  }
}
