import Foundation
import HTTPTesting
import HTTPTypes
import SwiftNARADigitalObjects
import SwiftNARADigitalObjectsModels

extension Demo {
  static func demonstrateRange(
    client: DigitalObjectsClient, directory: URL, fixtures: URL,
    transport: MockTransport
  ) async throws {
    let records = try JSONSerialization.jsonObject(
      with: Data(contentsOf: fixtures.appendingPathComponent("attribution.json")))
    guard let records = records as? [[String: Any]],
      let record = records.first(where: { $0["file"] as? String == "range-fdr-jpeg.bin" })
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
    let bytes = try Data(contentsOf: fixtures.appendingPathComponent("range-fdr-jpeg.bin"))
    transport.enqueue(.success(.init(chunks: [bytes], headers: fields, status: .partialContent)))
    let object = try DigitalObjectReference(
      naID: "122178160", objectID: "122178162", url: capture.url)
    let source = try DigitalObjectRangeReference(
      entityTag: capture.expectedETag, object: object,
      totalByteCount: capture.totalByteCount)
    let receipt = try await client.downloadRange(
      DigitalObjectByteRange(lowerBound: 16, upperBound: 47),
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
