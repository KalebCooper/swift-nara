import Foundation
import HTTPTesting
import HTTPTypes
import SwiftNARACatalogBulk
import SwiftNARACatalogBulkModels

/// A header name recorded in a fixture that `HTTPField.Name` refuses to parse.
struct DemoFixtureHeaderError: Error, CustomStringConvertible {
  let description: String
}

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
      let objects = line.record.digitalObjects ?? []
      let completeOCRCount = objects.filter { $0.completeExtractedText != nil }.count
      let partnerOCRCount = objects.filter { $0.otherExtractedText != nil }.count
      print("  complete OCR objects \(completeOCRCount), partner OCR objects \(partnerOCRCount)")
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
    let notModifiedHeadersData = try Data(
      contentsOf: fixtures.appendingPathComponent("refresh-not-modified.headers.json"))
    let recordedHeaders = try JSONDecoder().decode(
      [String: String].self, from: notModifiedHeadersData)
    var notModifiedFields = HTTPFields()
    for (name, value) in recordedHeaders.sorted(by: { $0.key < $1.key }) {
      guard let fieldName = HTTPField.Name(name) else {
        throw DemoFixtureHeaderError(
          description: "Recorded refresh header name \"\(name)\" is not a valid HTTP field name")
      }
      notModifiedFields.append(HTTPField(name: fieldName, value: value))
    }
    // Answer 6: the recorded 304, replayed against the shard already saved above.
    transport.enqueue(
      .success(MockTransport.Answer(chunks: [], headers: notModifiedFields, status: .notModified)))
    // Answer 7: the recorded 200, replayed into a second, different destination.
    transport.enqueue(.success(MockTransport.Answer(chunks: [shard])))
    let refreshCondition = try ShardCondition.ifNoneMatch("\"4ee6006efb1a7923711c088aaf8626a0\"")
    let refreshReference = try ShardReference(
      key: "descriptions/collections/coll_FDR-FDRMSF/coll_FDR-FDRMSF-1.jsonl")
    let notModifiedResult = try await client.refresh(
      refreshReference, condition: refreshCondition,
      to: directory.appendingPathComponent("fdr-refresh-not-modified.jsonl"))
    guard case .notModified(let retrieval) = notModifiedResult else {
      print("Refresh replay unexpectedly downloaded a new body")
      return
    }
    let etag = retrieval.headers.first { $0.name.lowercased() == "etag" }?.value ?? "no ETag"
    print("Refresh replay: not modified, ETag \(etag)")
    let downloadedResult = try await client.refresh(
      refreshReference, condition: refreshCondition,
      to: directory.appendingPathComponent("fdr-refresh-downloaded.jsonl"))
    guard case .downloaded(let refreshedReceipt) = downloadedResult else {
      print("Refresh replay unexpectedly reported not modified")
      return
    }
    let priorAttributes = try FileManager.default.attributesOfItem(atPath: receipt.fileURL.path)
    let priorByteCount = (priorAttributes[.size] as? Int) ?? -1
    print(
      "Refresh replay: downloaded \(refreshedReceipt.byteCount) bytes to \(refreshedReceipt.fileURL.lastPathComponent); prior file \(receipt.fileURL.lastPathComponent) remains \(priorByteCount) bytes"
    )
    try await demonstrateRange(
      client: client, directory: directory, fixtures: fixtures, transport: transport)
    try await demonstrateResume(in: directory)
    try await demonstrateArchive(
      client: client, directory: directory, fixtures: fixtures, transport: transport)
  }
}
