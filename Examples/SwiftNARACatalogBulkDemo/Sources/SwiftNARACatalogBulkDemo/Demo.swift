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
    let authorityDirectory = try Data(
      contentsOf: fixtures.appendingPathComponent("directory-authority-records.xml"))
    let first = try Data(contentsOf: fixtures.appendingPathComponent("manifest-first.xml"))
    let second = try Data(contentsOf: fixtures.appendingPathComponent("manifest-second.xml"))
    let shard = try Data(contentsOf: fixtures.appendingPathComponent("fdr.jsonl"))
    let person = try Data(contentsOf: fixtures.appendingPathComponent("person.jsonl"))
    let transport = MockTransport(
      results: [authorityDirectory, first, second, shard, person].map {
        .success(Response(body: $0, status: .ok))
      })
    // A fixed receipt instant makes this recorded example repeatable.
    let client = CatalogBulkClient(
      configuration: try CatalogBulkConfiguration(
        userAgent: "(swift-nara demo, https://github.com/KalebCooper/swift-nara)"),
      retrievalTime: { Date(timeIntervalSince1970: 1_790_208_000) }, transport: transport)
    let directoryQuery = try BulkDirectoryQuery(directory: .authorityRecords, maxKeys: 20)
    var partitionCount = 0
    for try await partition in client.partitions(matching: directoryQuery) {
      partitionCount += 1
      print("Authority partition \(partitionCount): \(partition.prefix)")
    }
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
      let description = line.record.archivalDescription
      let level = description?.levelOfDescription?.rawValue ?? "unknown level"
      let productionYear =
        description?.productionDates?.first?.year.map(String.init) ?? "no production date"
      let ancestorCount = description?.ancestors?.count ?? 0
      let restrictionStatus = description?.accessRestriction?.status?.rawValue ?? "undeclared"
      let digitalObjectsState: String
      switch line.record.isMetadataOnly {
      case .some(true): digitalObjectsState = "metadata-only"
      case .some(false): digitalObjectsState = "available"
      case .none: digitalObjectsState = "not declared"
      }
      print(
        "  level \(level), production date \(productionYear), ancestors \(ancestorCount), access restriction \(restrictionStatus), digital objects \(digitalObjectsState)"
      )
      let transcriptions = line.record.transcriptions ?? []
      var machineGeneratedTrue = 0
      var machineGeneratedFalse = 0
      var machineGeneratedNotDeclared = 0
      for transcription in transcriptions {
        switch transcription.isAIMachineGenerated {
        case .some(true): machineGeneratedTrue += 1
        case .some(false): machineGeneratedFalse += 1
        case .none: machineGeneratedNotDeclared += 1
        }
      }
      print(
        "  transcriptions \(transcriptions.count), machine-generated true \(machineGeneratedTrue), false \(machineGeneratedFalse), not declared \(machineGeneratedNotDeclared)"
      )
    }
    let authorityReceipt = try await client.download(
      ShardReference(key: "authority-records/person/person-1.jsonl"),
      to: directory.appendingPathComponent("person.jsonl"))
    for try await line in try CatalogLineSequence(shard: authorityReceipt) {
      let authority = line.record.authorityRecord
      print(
        "First person authority heading \(authority?.heading ?? "no heading"), type \(authority?.authorityType?.rawValue ?? "no type")"
      )
      break
    }
    print(
      "Read \(count) local records from \(receipt.byteCount) saved bytes; \(transport.requests.count) recorded HTTP responses."
    )
  }
}
