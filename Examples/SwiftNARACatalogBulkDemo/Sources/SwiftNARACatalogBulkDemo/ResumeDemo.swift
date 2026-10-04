import Foundation
import HTTPTesting
import SwiftNARACatalogBulk
import SwiftNARACatalogBulkModels

extension Demo {
  static func demonstrateResume(in directory: URL) async throws {
    // Local lifecycle example: synthetic bytes and headers, not a provider capture.
    let transport = MockTransport(answers: [
      .success(
        .init(
          chunks: [Data("abcd".utf8)],
          headers: [
            .contentRange: "bytes 0-3/8", .eTag: "\"demo\"",
          ], status: .partialContent)),
      .success(.init(chunks: [], status: .ok)),
    ])
    let client = CatalogBulkClient(
      configuration: try .init(maximumRangeBytes: 4, userAgent: "swift-nara offline demo"),
      retrievalTime: { Date(timeIntervalSince1970: 1_790_208_000) }, transport: transport)
    let reference = try BulkRangeReference(
      entityTag: "\"demo\"", key: "descriptions/demo.jsonl", totalByteCount: 8)
    let initial = try client.beginDownload(reference, in: directory)
    let destination = directory.appendingPathComponent("resumed-demo.bin")
    do {
      _ = try await client.resumeDownload(initial, to: destination)
      throw CocoaError(.fileReadCorruptFile)
    } catch let failure as BulkDownloadFailure {
      guard failure.checkpoint?.committedByteCount == 4,
        case .range(.rangeNotHonored) = failure.reason
      else { throw failure }
      print("Synthetic resume: retained 4 validated bytes after a refused HTTP 200.")
    }
    transport.enqueue(
      .success(
        .init(
          chunks: [Data("efgh".utf8)],
          headers: [
            .contentRange: "bytes 4-7/8", .eTag: "\"demo\"",
          ], status: .partialContent)))
    // An older caller checkpoint reloads the newer durable sidecar.
    let receipt = try await client.resumeDownload(initial, to: destination)
    guard try Data(contentsOf: receipt.fileURL) == Data("abcdefgh".utf8) else {
      throw CocoaError(.fileReadCorruptFile)
    }
    try client.discardDownload(receipt.checkpoint)
    print(
      "Synthetic resume: published 8 exact bytes and discarded retained state; no live request.")
  }
}
