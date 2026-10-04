import Foundation
import HTTPTesting
import SwiftNARACatalogBulk
import SwiftNARACatalogBulkModels

extension Demo {
  static func demonstrateArchive(
    client: CatalogBulkClient, directory: URL, fixtures: URL, transport: MockTransport
  ) async throws {
    let bytes = try Data(contentsOf: fixtures.appendingPathComponent("synthetic-archive.zip"))
    let reference = try BulkArchiveReference(key: "zip/synthetic-example.zip")
    let limits = try BulkArchiveDownloadLimits(
      maximumByteCount: 512, maximumWorkspaceBytes: 3_000_000)
    transport.enqueue(.success(.init(chunks: [bytes], headers: [.contentLength: "229"])))
    let receipt = try await client.downloadArchive(
      reference, to: directory.appendingPathComponent("synthetic.zip"), limits: limits)
    guard receipt.byteCount == 229,
      receipt.sha256 == "93b9503f61b3b89fd29a3de15c6309be948c4c34af22bb42fb61d32d79214da9"
    else { throw CocoaError(.fileReadCorruptFile) }
    let checkpoint = try client.beginArchiveDownload(
      reference.rangeReference(entityTag: "\"synthetic\"", totalByteCount: 229),
      in: directory, limits: limits)
    transport.enqueue(
      .success(
        .init(
          chunks: [bytes],
          headers: [
            .contentRange: "bytes 0-228/229", .eTag: "\"synthetic\"",
          ], status: .partialContent)))
    let resumed = try await client.resumeArchiveDownload(
      checkpoint, to: directory.appendingPathComponent("synthetic-resumed.zip"), limits: limits)
    guard resumed.sha256 == receipt.sha256,
      try Data(contentsOf: resumed.fileURL) == bytes
    else { throw CocoaError(.fileReadCorruptFile) }
    try client.discardDownload(checkpoint)
    print(
      "Synthetic ZIP: acquired and resumed 229 exact bytes with separate SHA-256; no extraction or live request."
    )
  }
}
