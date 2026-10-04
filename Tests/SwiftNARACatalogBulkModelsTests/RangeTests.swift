import Foundation
import SwiftNARACatalogBulkModels
import SwiftNARACatalogBulkTestSupport
import Testing

@Suite(.timeLimit(.minutes(suiteTimeLimitMinutes)))
struct RangeTests {
  @Test("Range bounds reject negative reversed and overflowing selections")
  func bounds() throws {
    let invalid: [(Int64, Int64)] = [(-1, 2), (3, 2), (0, Int64.max)]
    for (lower, upper) in invalid {
      #expect(throws: BulkRangeError.invalidRange) {
        try BulkByteRange(lowerBound: lower, upperBound: upper)
      }
    }
    let range = try BulkByteRange(lowerBound: 16, upperBound: 47)
    #expect(range.byteCount == 32 && range.headerValue == "bytes=16-47")
    #expect(try range.clipped(to: 32) == BulkByteRange(lowerBound: 16, upperBound: 31))
    #expect(throws: BulkRangeError.invalidRange) { try range.clipped(to: 16) }
  }

  @Test("Ranges preserve strong validators and encoded keys without broadening generic endpoints")
  func factories() throws {
    let reference = try BulkRangeReference(
      entityTag: "\"opaque-6\"", key: "zip/a %2F+?.zip", totalByteCount: 100, versionID: "a+b/=")
    let range = try BulkByteRange(lowerBound: 16, upperBound: 47)
    let endpoint = Endpoint.range(range, of: reference)
    let request = CatalogBulkRequest.range(range, of: reference)
    #expect(endpoint.path == "/zip/a%20%252F%2B%3F.zip?versionId=a%2Bb%2F%3D")
    #expect(reference.entityTag == "\"opaque-6\"")
    #expect(endpoint.range == range && endpoint.rangeReference == reference)
    #expect(request.resolution == .endpoint(endpoint))
    #expect(Endpoint<BulkRangeReceipt>(path: endpoint.path) == nil)
    #expect(Endpoint<ShardReceipt>(path: endpoint.path) == nil)
  }

  @Test("Reference validation rejects weak tags lists wildcard paths and meaningless versions")
  func references() throws {
    for tag in ["W/\"abc\"", "*", "\"a\",\"b\"", "abc", "\"a\nb\"", "\"a b\""] {
      #expect(throws: BulkRangeError.invalidReference) {
        try BulkRangeReference(entityTag: tag, key: "zip/a.zip", totalByteCount: 1)
      }
    }
    for key in [
      "zip/../a.zip", "/zip/a.zip", "zip//a.zip", "other/a.zip", "descriptions/a.zip",
      "zip/a.jsonl", "zip/a\\b.zip",
    ] {
      #expect(throws: BulkRangeError.invalidReference) {
        try BulkRangeReference(entityTag: "\"abc\"", key: key, totalByteCount: 1)
      }
    }
    for version in ["", "null", "bad\nversion"] {
      #expect(throws: BulkRangeError.invalidReference) {
        try BulkRangeReference(
          entityTag: "\"abc\"", key: "zip/a.zip", totalByteCount: 1, versionID: version)
      }
    }
    #expect(throws: BulkRangeError.invalidReference) {
      try BulkRangeReference(entityTag: "\"abc\"", key: "zip/a.zip", totalByteCount: 0)
    }
  }
}
