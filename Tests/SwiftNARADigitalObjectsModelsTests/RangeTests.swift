import Foundation
import SwiftNARADigitalObjectsModels
import SwiftNARADigitalObjectsTestSupport
import Testing

@Suite(.timeLimit(.minutes(suiteTimeLimitMinutes)))
struct RangeTests {
  @Test("Range bounds reject negative reversed and overflowing selections")
  func bounds() throws {
    let invalid: [(Int64, Int64)] = [(-1, 2), (3, 2), (0, Int64.max)]
    for (lower, upper) in invalid {
      #expect(throws: DigitalObjectRangeError.invalidRange) {
        try DigitalObjectByteRange(lowerBound: lower, upperBound: upper)
      }
    }
    let range = try DigitalObjectByteRange(lowerBound: 16, upperBound: 47)
    #expect(range.byteCount == 32 && range.headerValue == "bytes=16-47")
    #expect(try range.clipped(to: 32) == DigitalObjectByteRange(lowerBound: 16, upperBound: 31))
    #expect(throws: DigitalObjectRangeError.invalidRange) { try range.clipped(to: 16) }
  }

  @Test("Range factories preserve archival identity and exact transport paths")
  func factories() throws {
    let object = try DigitalObjectReference(
      naID: "1", objectID: "2",
      url: "https://s3.amazonaws.com/NARAprodstorage/opastorage/live/a%20b.jpg")
    let reference = try DigitalObjectRangeReference(
      entityTag: "\"opaque-6\"", object: object,
      totalByteCount: 100)
    let range = try DigitalObjectByteRange(lowerBound: 16, upperBound: 47)
    let endpoint = Endpoint.range(range, of: reference)
    let request = DigitalObjectRequest.range(range, of: reference)
    #expect(endpoint.path == "/medialive/a%20b.jpg")
    #expect(endpoint.range == range && endpoint.rangeReference == reference)
    #expect(
      reference.object.url == "https://s3.amazonaws.com/NARAprodstorage/opastorage/live/a%20b.jpg")
    #expect(request.resolution == .endpoint(endpoint))
    #expect(Endpoint<DigitalObjectRangeReceipt>(link: object.transportURL)?.range == nil)
  }

  @Test("Range reference validation refuses weak or multiple validators and invalid length")
  func references() throws {
    let object = try DigitalObjectReference(
      naID: "1", objectID: nil,
      url: "https://catalog.archives.gov/medialz/a.jpg")
    for tag in ["W/\"abc\"", "*", "\"a\",\"b\"", "abc", "\"a\nb\"", "\"a b\""] {
      #expect(throws: DigitalObjectRangeError.invalidReference) {
        try DigitalObjectRangeReference(entityTag: tag, object: object, totalByteCount: 1)
      }
    }
    #expect(throws: DigitalObjectRangeError.invalidReference) {
      try DigitalObjectRangeReference(entityTag: "\"abc\"", object: object, totalByteCount: 0)
    }
  }
}
