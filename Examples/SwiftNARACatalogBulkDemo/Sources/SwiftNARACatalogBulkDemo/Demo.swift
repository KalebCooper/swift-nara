import Foundation
import HTTPTesting
import SwiftNARACatalogBulk
import SwiftNARACatalogBulkModels

@main
struct Demo {
  static func main() async throws {
    guard CommandLine.arguments.count == 2 else {
      print("Usage: SwiftNARACatalogBulkDemo PATH_TO_RECORDED_FIXTURES")
      return
    }
    let fixtures = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
    let first = try Data(contentsOf: fixtures.appendingPathComponent("manifest-first.xml"))
    let second = try Data(contentsOf: fixtures.appendingPathComponent("manifest-second.xml"))
    let shard = try Data(contentsOf: fixtures.appendingPathComponent("fdr.jsonl"))
    let transport = MockTransport(
      results: [first, second, shard].map { .success(Response(body: $0, status: .ok)) })
    // A fixed receipt instant makes this recorded example repeatable.
    let client = CatalogBulkClient(
      configuration: try CatalogBulkConfiguration(
        userAgent: "(swift-nara demo, https://github.com/KalebCooper/swift-nara)"),
      retrievalTime: { Date(timeIntervalSince1970: 1_790_208_000) }, transport: transport)
    let query = try ManifestQuery(maxKeys: 4, prefix: "descriptions/record-groups/rg_11/")
    var pageCount = 0
    for try await page in client.manifestPages(matching: query) {
      pageCount += 1
      print(
        "Manifest page \(pageCount): \(page.value.objects.count) objects, \(page.body.count) original bytes"
      )
      if pageCount == 2 { break }
    }
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      "nara-demo-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: directory) }
    let receipt = try await client.download(
      ShardReference(key: "descriptions/collections/coll_FDR-FDRMSF/coll_FDR-FDRMSF-1.jsonl"),
      to: directory.appendingPathComponent("fdr.jsonl"))
    var count = 0
    for try await line in try CatalogLineSequence(shard: receipt) {
      count += 1
      print(
        "Line \(line.lineNumber), byte \(line.byteOffset), NAID \(line.record.naID): \(line.record.title ?? "Untitled")"
      )
    }
    print(
      "Read \(count) local records from \(receipt.byteCount) saved bytes; \(transport.requests.count) recorded HTTP responses."
    )
  }
}
