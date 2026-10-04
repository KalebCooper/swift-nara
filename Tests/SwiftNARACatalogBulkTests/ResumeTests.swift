import Foundation
import HTTPCore
import HTTPTesting
import HTTPTypes
@testable import SwiftNARACatalogBulk
import SwiftNARACatalogBulkModels
import SwiftNARACatalogBulkTestSupport
import Testing

@Suite(.timeLimit(.minutes(suiteTimeLimitMinutes)))
struct ResumeTests {
  @Test("Already cancelled begin and resume do no file or network work")
  func cancelledBeforeStart() async throws {
    let directory = try directory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let transport = MockTransport()
    let client = try client(transport)
    let source = try reference(4)
    let checkpoint = try client.beginDownload(source, in: directory)
    let gate = AsyncStream<Void>.makeStream()
    let task = Task {
      var iterator = gate.stream.makeAsyncIterator()
      _ = await iterator.next()
      do {
        _ = try client.beginDownload(source, in: directory)
        Issue.record("Expected cancellation before begin")
      } catch {
        guard let error = error as? CatalogBulkError, case .cancelled = error else {
          Issue.record("Expected cancellation"); return
        }
      }
      let failed = try await failure {
        _ = try await client.resumeDownload(checkpoint, to: directory.appendingPathComponent("out"))
      }
      guard case .cancelled = failed.reason else { Issue.record("Expected cancellation"); return }
      #expect(failed.checkpoint == nil)
    }
    task.cancel()
    gate.continuation.finish()
    try await task.value
    #expect(transport.requests.isEmpty)
    #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).count == 1)
  }

  @Test("A failed checkpoint write rolls back bytes and preserves the last durable boundary")
  func checkpointWriteFailure() async throws {
    let directory = try directory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let bytes = Data("abcdefgh".utf8)
    let transport = transport(bytes)
    var failing = try client(transport)
    let checkpoint = try failing.beginDownload(reference(8), in: directory)
    failing.saveCheckpoint = { _ in throw CocoaError(.fileWriteOutOfSpace) }
    let failure = try await failure {
      _ = try await failing.resumeDownload(checkpoint, to: directory.appendingPathComponent("out"))
    }
    #expect(failure.checkpoint?.committedByteCount == 0)
    #expect(try Data(contentsOf: checkpoint.partialFileURL).isEmpty)
    #expect(
      try JSONDecoder().decode(
        BulkDownloadCheckpoint.self,
        from: Data(contentsOf: checkpoint.checkpointURL)
      ).committedByteCount == 0)
    let receipt = try await client(transport).resumeDownload(
      checkpoint, to: directory.appendingPathComponent("out"))
    #expect(try Data(contentsOf: receipt.fileURL) == bytes)
  }

  @Test("Concurrent resumes conflict and cancellation retains the completed range")
  func concurrencyAndCancellation() async throws {
    let directory = try directory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let ready = AsyncStream<Void>.makeStream()
    let transport = MockTransport(answers: [
      .success(
        .init(
          chunks: [Data("abcd".utf8)],
          headers: [.contentRange: "bytes 0-3/8", .eTag: "\"tag\""], status: .partialContent)),
      .success(
        .init(
          body: {
            ready.continuation.yield(())
            return StreamedBody(
              AsyncStream<Data> { continuation in
                continuation.yield(Data("e".utf8))
              })
          }, headers: [.contentRange: "bytes 4-7/8", .eTag: "\"tag\""], status: .partialContent)),
    ])
    let client = try client(transport)
    let checkpoint = try client.beginDownload(reference(8), in: directory)
    let task = Task {
      try await failure {
        _ = try await client.resumeDownload(checkpoint, to: directory.appendingPathComponent("one"))
      }
    }
    var iterator = ready.stream.makeAsyncIterator()
    _ = await iterator.next()
    let conflict = try await failure {
      _ = try await client.resumeDownload(checkpoint, to: directory.appendingPathComponent("two"))
    }
    guard case .downloadState(.writerConflict) = conflict.reason else {
      Issue.record("Expected writer conflict: \(conflict.reason)"); task.cancel(); return
    }
    task.cancel()
    let cancelled = try await task.value
    guard case .cancelled = cancelled.reason else {
      Issue.record("Expected cancellation: \(cancelled.reason)"); return
    }
    #expect(cancelled.checkpoint?.committedByteCount == 4)
    #expect(try Data(contentsOf: checkpoint.partialFileURL) == Data("abcd".utf8))
    #expect(transport.requests.count == 2)
  }

  @Test("A simulated crash tail is discarded before requesting the durable continuation")
  func crashRecovery() async throws {
    let directory = try directory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let checkpoint = try await paused(in: directory)
    let file = try FileHandle(forWritingTo: checkpoint.partialFileURL)
    try file.seekToEnd()
    try file.write(contentsOf: Data("uncommitted crash bytes".utf8))
    try file.synchronize()
    try file.close()
    let transport = transport(Data("abcdefgh".utf8))
    let receipt = try await client(transport).resumeDownload(
      checkpoint, to: directory.appendingPathComponent("out"))
    #expect(transport.requests.first?.request.headerFields[.range] == "bytes=4-7")
    #expect(try Data(contentsOf: receipt.fileURL) == Data("abcdefgh".utf8))
  }

  @Test("Existing destinations and mismatched source requests fail before transport")
  func destinationAndSourcePreflight() async throws {
    let directory = try directory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let transport = MockTransport()
    let client = try client(transport)
    let checkpoint = try client.beginDownload(reference(4), in: directory)
    let destination = directory.appendingPathComponent("out")
    try Data("keep".utf8).write(to: destination)
    let existing = try await failure {
      _ = try await client.resumeDownload(checkpoint, to: destination)
    }
    #expect(existing.checkpoint == nil)
    #expect(try Data(contentsOf: destination) == Data("keep".utf8))
    try FileManager.default.removeItem(at: destination)
    try FileManager.default.createSymbolicLink(
      at: destination, withDestinationURL: directory.appendingPathComponent("absent"))
    _ = try await failure {
      _ = try await client.resumeDownload(checkpoint, to: destination)
    }
    let mismatch = try await failure {
      _ = try await client.send(
        .resumableDownload(reference(8)), checkpoint: checkpoint,
        to: directory.appendingPathComponent("new"))
    }
    guard case .invalidConfiguration = mismatch.reason else {
      Issue.record("Expected source mismatch"); return
    }
    #expect(transport.requests.isEmpty)
    #expect(try Data(contentsOf: checkpoint.partialFileURL).isEmpty)
  }

  @Test("All call forms reassemble full fixture bytes through synthetic ranges")
  func equivalence() async throws {
    let bytes = try Fixture.fdr.data()
    let directory = try directory()
    defer { try? FileManager.default.removeItem(at: directory) }
    for form in 0..<4 {
      let transport = transport(bytes)
      let client = try client(transport, maximumBytes: 30_001)
      let source = try reference(Int64(bytes.count))
      let checkpoint = try client.beginDownload(source, in: directory)
      #expect(transport.requests.isEmpty)
      let destination = directory.appendingPathComponent("out-\(form)")
      let receipt: BulkDownloadReceipt
      switch form {
      case 0: receipt = try await client.resumeDownload(checkpoint, to: destination)
      case 1:
        let request = CatalogBulkRequest.resumableDownload(source)
        receipt = try await client.value(for: request, checkpoint: checkpoint, to: destination)
      case 2:
        receipt = try await client.send(
          .resumableDownload(source), checkpoint: checkpoint, to: destination)
      default:
        receipt = try await client.value(
          for: .continued(source), checkpoint: checkpoint, to: destination)
      }
      #expect(receipt.byteCount == Int64(bytes.count))
      #expect(receipt.checkpoint.reference == source)
      #expect(try Data(contentsOf: destination) == bytes)
      #expect(transport.requests.count > 1)
      try client.discardDownload(checkpoint)
      #expect(!FileManager.default.fileExists(atPath: checkpoint.partialFileURL.path))
      #expect(!FileManager.default.fileExists(atPath: checkpoint.checkpointURL.path))
      #expect(try Data(contentsOf: destination) == bytes)
    }
  }

  @Test("A newer committed sidecar survives a failure just after its write")
  func newerSidecar() async throws {
    let directory = try directory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let transport = transport(Data("abcdefgh".utf8))
    var failing = try client(transport)
    let checkpoint = try failing.beginDownload(reference(8), in: directory)
    failing.saveCheckpoint = {
      try BulkDownloadFile.persist($0)
      throw CocoaError(.fileWriteOutOfSpace)
    }
    let interrupted = try await failure {
      _ = try await failing.resumeDownload(checkpoint, to: directory.appendingPathComponent("out"))
    }
    #expect(interrupted.checkpoint?.committedByteCount == 0)
    #expect(try Data(contentsOf: checkpoint.partialFileURL) == Data("abcd".utf8))
    let receipt = try await client(transport).resumeDownload(
      checkpoint, to: directory.appendingPathComponent("out"))
    #expect(transport.requests.count == 2)
    #expect(transport.requests.last?.request.headerFields[.range] == "bytes=4-7")
    #expect(try Data(contentsOf: receipt.fileURL) == Data("abcdefgh".utf8))
  }

  @Test("Changed partial files and corrupt or linked sidecars fail before transport")
  func ownershipFailures() async throws {
    let directory = try directory()
    defer { try? FileManager.default.removeItem(at: directory) }
    for variant in 0..<6 {
      let transport = MockTransport()
      let client = try client(transport)
      let checkpoint = try client.beginDownload(reference(8), in: directory)
      let other = directory.appendingPathComponent("user-\(variant)")
      try Data("keep".utf8).write(to: other)
      switch variant {
      case 0: try FileManager.default.removeItem(at: checkpoint.partialFileURL)
      case 1:
        try FileManager.default.moveItem(
          at: checkpoint.partialFileURL,
          to: directory.appendingPathComponent("original"))
        try Data().write(to: checkpoint.partialFileURL)
      case 2:
        try FileManager.default.removeItem(at: checkpoint.partialFileURL)
        try FileManager.default.createSymbolicLink(
          at: checkpoint.partialFileURL, withDestinationURL: other)
      case 3: try Data("invalid".utf8).write(to: checkpoint.checkpointURL)
      case 4:
        try FileManager.default.removeItem(at: checkpoint.checkpointURL)
        try FileManager.default.createSymbolicLink(
          at: checkpoint.checkpointURL, withDestinationURL: other)
      default: try Data(repeating: 0, count: 1_048_577).write(to: checkpoint.checkpointURL)
      }
      _ = try await failure {
        _ = try await client.resumeDownload(checkpoint, to: directory.appendingPathComponent("out"))
      }
      #expect(transport.requests.isEmpty)
      #expect(try Data(contentsOf: other) == Data("keep".utf8))
      #expect(throws: CatalogBulkError.self) { try client.discardDownload(checkpoint) }
      #expect(try Data(contentsOf: other) == Data("keep".utf8))
    }
  }

  @Test("A destination created during transfer is never replaced")
  func publicationRace() async throws {
    let directory = try directory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let destination = directory.appendingPathComponent("out")
    let transport = MockTransport()
    transport.setHandler(forPath: "/descriptions/a.jsonl") { _ in
      do {
        try Data("winner".utf8).write(to: destination)
        return .success(
          .init(
            chunks: [Data("abcd".utf8)],
            headers: [.contentRange: "bytes 0-3/4", .eTag: "\"tag\""], status: .partialContent))
      } catch { return .failure(.transport(kind: .other, underlying: error)) }
    }
    let client = try client(transport)
    let checkpoint = try client.beginDownload(reference(4), in: directory)
    let failed = try await failure {
      _ = try await client.resumeDownload(checkpoint, to: destination)
    }
    #expect(failed.checkpoint?.committedByteCount == 4)
    #expect(try Data(contentsOf: destination) == Data("winner".utf8))
    let unused = MockTransport()
    let recovered = try await self.client(unused).resumeDownload(
      checkpoint, to: directory.appendingPathComponent("recovered"))
    #expect(unused.requests.isEmpty)
    #expect(try Data(contentsOf: recovered.fileURL) == Data("abcd".utf8))
    let extra = checkpoint.partialFileURL.deletingLastPathComponent().appendingPathComponent("keep")
    try Data("unrelated".utf8).write(to: extra)
    try client.discardDownload(checkpoint)
    #expect(try Data(contentsOf: extra) == Data("unrelated".utf8))
    #expect(try Data(contentsOf: recovered.fileURL) == Data("abcd".utf8))
    #expect(try Data(contentsOf: destination) == Data("winner".utf8))
  }

  @Test("Equal-length prefix corruption is detected before a request or append")
  func sameSizeCorruption() async throws {
    let directory = try directory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let checkpoint = try await paused(in: directory)
    let file = try FileHandle(forWritingTo: checkpoint.partialFileURL)
    try file.write(contentsOf: Data("xxxx".utf8))
    try file.close()
    let transport = MockTransport()
    let client = try client(transport)
    let failed = try await failure {
      _ = try await client.resumeDownload(checkpoint, to: directory.appendingPathComponent("out"))
    }
    guard case .downloadState(.integrityMismatch) = failed.reason else {
      Issue.record("Expected integrity mismatch: \(failed.reason)"); return
    }
    #expect(failed.checkpoint == nil)
    #expect(transport.requests.isEmpty)
    #expect(try Data(contentsOf: checkpoint.partialFileURL) == Data("xxxx".utf8))
    try client.discardDownload(checkpoint)
  }

  @Test("Wrong HTTP status validators offsets and encoding preserve the zero boundary")
  func sourceFailures() async throws {
    let directory = try directory()
    defer { try? FileManager.default.removeItem(at: directory) }
    for variant in 0..<8 {
      var fields: HTTPFields = [.contentRange: "bytes 0-3/8", .eTag: "\"tag\""]
      let status = [200, 412, 416, 206, 206, 206, 206, 206][variant]
      switch variant {
      case 3: fields[.eTag] = "W/\"tag\""
      case 4: fields[.eTag] = nil
      case 5: fields[.eTag] = "\"changed\""
      case 6: fields[.contentRange] = "bytes 1-4/8"
      case 7: fields[.contentEncoding] = "gzip"
      default: break
      }
      let transport = MockTransport(answers: [
        .success(.init(chunks: [Data("abcd".utf8)], headers: fields, status: .init(code: status)))
      ])
      let client = try client(transport)
      let checkpoint = try client.beginDownload(reference(8), in: directory)
      let failed = try await failure {
        _ = try await client.resumeDownload(checkpoint, to: directory.appendingPathComponent("out"))
      }
      #expect(failed.checkpoint?.committedByteCount == 0)
      #expect(try Data(contentsOf: checkpoint.partialFileURL).isEmpty)
      #expect(transport.requests.count == 1)
      if status == 200 {
        guard case .range(.rangeNotHonored) = failed.reason else {
          Issue.record("Expected restart required"); continue
        }
      }
      if status == 412 || status == 416 {
        guard case .transport(.httpStatus(_, let code, _)) = failed.reason else {
          Issue.record("Expected exact HTTP failure"); continue
        }
        #expect(code == status)
      }
    }
  }

  @Test("UTF-8 and line boundaries are opaque until the whole file is reassembled")
  func textBoundaries() async throws {
    let directory = try directory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let bytes = Data("{\"title\":\"😀\"}\n{\"title\":\"x\"}\n".utf8)
    let transport = transport(bytes)
    let client = try client(transport, maximumBytes: 3)
    let checkpoint = try client.beginDownload(reference(Int64(bytes.count)), in: directory)
    let receipt = try await client.resumeDownload(
      checkpoint, to: directory.appendingPathComponent("out"))
    #expect(try Data(contentsOf: receipt.fileURL) == bytes)
  }

  private func client(_ transport: MockTransport, maximumBytes: Int64 = 4) throws
    -> CatalogBulkClient
  {
    CatalogBulkClient(
      configuration: try .init(maximumRangeBytes: maximumBytes, userAgent: "swift-nara tests"),
      retrievalTime: { Date(timeIntervalSince1970: 1234) }, transport: transport)
  }

  private func directory() throws -> URL {
    let value = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: value, withIntermediateDirectories: false)
    return value
  }

  private func failure(_ operation: () async throws -> Void) async throws -> BulkDownloadFailure {
    do { try await operation() } catch let error as BulkDownloadFailure { return error }
    throw CocoaError(.fileReadCorruptFile)
  }

  private func paused(in directory: URL) async throws -> BulkDownloadCheckpoint {
    let transport = MockTransport(answers: [
      .success(
        .init(
          chunks: [Data("abcd".utf8)],
          headers: [.contentRange: "bytes 0-3/8", .eTag: "\"tag\""], status: .partialContent)),
      .success(.init(chunks: [], status: .ok)),
    ])
    let client = try client(transport)
    let checkpoint = try client.beginDownload(reference(8), in: directory)
    let interrupted = try await failure {
      _ = try await client.resumeDownload(checkpoint, to: directory.appendingPathComponent("out"))
    }
    let durable = try #require(interrupted.checkpoint)
    #expect(durable.committedByteCount == 4)
    return durable
  }

  private func reference(_ count: Int64) throws -> BulkRangeReference {
    try .init(entityTag: "\"tag\"", key: "descriptions/a.jsonl", totalByteCount: count)
  }

  private func transport(_ bytes: Data) -> MockTransport {
    let transport = MockTransport()
    transport.setHandler(forPath: "/descriptions/a.jsonl") { request in
      let fields = request.headerFields[.range]?.dropFirst(6).split(separator: "-") ?? []
      guard fields.count == 2, let lower = Int(fields[0]), let upper = Int(fields[1]),
        lower >= 0, upper >= lower, upper < bytes.count
      else { return .failure(.cancelled) }
      return .success(
        .init(
          chunks: [bytes.subdata(in: lower..<(upper + 1))],
          headers: [.contentRange: "bytes \(lower)-\(upper)/\(bytes.count)", .eTag: "\"tag\""],
          status: .partialContent))
    }
    return transport
  }
}

extension CatalogBulkRequest where Response == BulkDownloadReceipt {
  fileprivate static func continued(_ reference: BulkRangeReference) -> Self {
    Self(endpoint: .resumableDownload(reference))
  }
}
