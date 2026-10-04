import Foundation
@testable import SwiftNARADigitalObjects
import SwiftNARADigitalObjectsTestSupport
import Testing

@Suite(.timeLimit(.minutes(suiteTimeLimitMinutes)))
struct DownloadIntegrityTests {
  @Test("Cancelled hashing does not read even an empty committed prefix")
  func cancellation() async throws {
    let ready = AsyncStream<Void>.makeStream()
    let task = Task {
      for await _ in ready.stream { break }
      let handle = FileHandle.nullDevice
      #expect(throws: CancellationError.self) {
        try DigitalObjectDownloadFile.digest(handle: handle, length: 0)
      }
    }
    task.cancel()
    ready.continuation.finish()
    await task.value
  }

  @Test("SHA-256 reads only the committed prefix and handles multiple bounded reads")
  func digests() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: url) }
    try Data(repeating: 97, count: 1_000_000).write(to: url, options: .withoutOverwriting)
    let handle = try FileHandle(forReadingFrom: url)
    defer { try? handle.close() }
    #expect(
      try DigitalObjectDownloadFile.digest(handle: handle, length: 0)
        == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
    #expect(
      try DigitalObjectDownloadFile.digest(handle: handle, length: 1)
        == "ca978112ca1bbdcafac231b39a23dc4da786eff8147c4e72b9807785afee48bb")
    #expect(try handle.offset() == 1)
    #expect(
      try DigitalObjectDownloadFile.digest(handle: handle, length: 1_000_000)
        == "cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0")
    #expect(throws: (any Error).self) {
      try DigitalObjectDownloadFile.digest(handle: handle, length: 1_000_001)
    }
    #expect(throws: (any Error).self) {
      try DigitalObjectDownloadFile.digest(handle: handle, length: -1)
    }
  }
}
