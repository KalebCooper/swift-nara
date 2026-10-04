import Foundation
import HTTPTesting
import HTTPTypes
import SwiftNARACatalogBulk
import SwiftNARACatalogBulkModels

extension Demo {
  static func demonstrateRange(
    client: CatalogBulkClient, directory: URL, fixtures: URL,
    transport: MockTransport
  ) async throws {
    let records = try JSONSerialization.jsonObject(
      with: Data(contentsOf: fixtures.appendingPathComponent("attribution.json")))
    guard let records = records as? [[String: Any]],
      let record = records.first(where: { $0["file"] as? String == "range-fdr-jsonl.bin" })
    else {
      throw CocoaError(.fileReadCorruptFile)
    }
    let capture = try JSONDecoder().decode(
      RangeCapture.self,
      from: JSONSerialization.data(withJSONObject: record))
    var fields = HTTPFields()
    for (name, value) in capture.headers.sorted(by: { $0.key < $1.key }) {
      guard let field = HTTPField.Name(name) else { throw CocoaError(.fileReadCorruptFile) }
      fields.append(HTTPField(name: field, value: value))
    }
    let bytes = try Data(contentsOf: fixtures.appendingPathComponent("range-fdr-jsonl.bin"))
    transport.enqueue(.success(.init(chunks: [bytes], headers: fields, status: .partialContent)))
    let source = try BulkRangeReference(
      entityTag: capture.expectedETag,
      key: "descriptions/collections/coll_FDR-FDRMSF/coll_FDR-FDRMSF-1.jsonl",
      totalByteCount: capture.totalByteCount, versionID: capture.sourceVersionID)
    let receipt = try await client.downloadRange(
      BulkByteRange(lowerBound: 16, upperBound: 47),
      of: source, to: directory.appendingPathComponent("fragment.bin"))
    print(
      "Saved \(receipt.byteCount) partial bytes at offsets 16...47 of \(source.totalByteCount); not a complete file."
    )
  }
}

private struct RangeCapture: Decodable {
  let expectedETag: String
  let headers: [String: String]
  let sourceVersionID: String?
  let totalByteCount: Int64
  let url: String
}
