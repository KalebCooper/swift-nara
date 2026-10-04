import Foundation
import SwiftNARACatalogBulkModels
import SwiftNARACatalogBulkTestSupport
import Testing

@Suite(.timeLimit(.minutes(suiteTimeLimitMinutes)))
struct DigitalObjectTests {
  @Test("Original bulk captures retain labels and complete OCR")
  func bulkLabelsAndCompleteOCR() throws {
    let rg11 = try Fixture.rg11.data().split(separator: 10).flatMap {
      try CatalogRecord.decode(Data($0)).digitalObjects ?? []
    }
    let fdr = try Fixture.fdr.data().split(separator: 10).flatMap {
      try CatalogRecord.decode(Data($0)).digitalObjects ?? []
    }
    #expect(rg11.count == 58)
    #expect(fdr.count == 53)
    #expect(rg11.filter { $0.objectDescription != nil }.count == 38)
    #expect(rg11.filter { $0.objectDesignator != nil }.count == 22)
    #expect(rg11.filter { $0.completeExtractedText != nil }.count == 3)
    #expect(fdr.filter { $0.completeExtractedText != nil }.count == 4)
    let fold3 = try #require(rg11.first { $0.objectID == "63545806" })
    #expect(fold3.objectDescription == "Image provided by Fold3. (Page 1)")
    #expect(fold3.objectDesignator == "Fold3 File #6575614")
    let complete = try #require(rg11.first { $0.objectID == "68123585" })
    #expect(complete.completeExtractedText?.hasPrefix("\nO.H.B.\nReil 3d July\n") == true)
    #expect((rg11 + fdr).allSatisfy { $0.extractedTextAccuracy == nil })
    #expect((rg11 + fdr).allSatisfy { $0.otherExtractedText == nil && $0.thumbnailURL == nil })
  }

  @Test("Malformed metadata preserves raw kinds without coercion")
  func malformedMetadata() {
    // Synthetic wrong-shaped values, not additional provider captures.
    for value: JSONValue in [.null, .bool(true), .integer(1), .array([]), .object([:])] {
      let object = CatalogDigitalObject(
        source: .object([
          "completeExtractedText": value, "objectDescription": value, "objectDesignator": value,
          "otherExtractedText": value, "thumbnailUrl": value,
        ]))
      #expect(object.completeExtractedText == nil)
      #expect(object.objectDescription == nil)
      #expect(object.objectDesignator == nil)
      #expect(object.otherExtractedText == nil)
      #expect(object.thumbnailURL == nil)
      #expect(object.source["thumbnailUrl"] == value)
    }
    for value: JSONValue in [
      .null, .bool(true), .string("97"), .number(97.5), .unsignedInteger(.max),
    ] {
      let object = CatalogDigitalObject(source: .object(["extractedTextAccurracy": value]))
      #expect(object.extractedTextAccuracy == nil)
      #expect(object.source["extractedTextAccurracy"] == value)
    }
    let absent = CatalogDigitalObject(source: .object([:]))
    #expect(absent.completeExtractedText == nil && absent.extractedTextAccuracy == nil)
    #expect(absent.source["thumbnailUrl"] == nil)
  }

  @Test("Schema-only projections preserve contradictory accuracy and separate OCR")
  func schemaOnlyProjections() throws {
    // Synthetic schema-grounded fields, absent from the retained bulk captures.
    let bytes = Data(
      #"{"record":{"naId":42,"digitalObjects":[{"completeExtractedText":"complete","extractedText":"original","extractedTextAccurracy":101,"extractedTextAccuracy":50,"objectDescription":"","objectDesignator":"Page ii","otherExtractedText":"partner","thumbnailUrl":"https://example.org/thumb.jpg","future":null},{"objectId":"same"},{"objectId":"same"}]}}"#
        .utf8)
    let record = try CatalogRecord.decode(bytes)
    let objects = try #require(record.digitalObjects)
    #expect(objects.count == 3)
    #expect(objects[1].objectID == "same" && objects[2].objectID == "same")
    let object = objects[0]
    #expect(object.completeExtractedText == "complete")
    #expect(object.extractedText == "original")
    #expect(object.extractedTextAccuracy == 101)
    #expect(object.objectDescription == "")
    #expect(object.objectDesignator == "Page ii")
    #expect(object.otherExtractedText == "partner")
    #expect(object.thumbnailURL == "https://example.org/thumb.jpg")
    #expect(object.source["future"] == .null)
    #expect(object.source["extractedTextAccuracy"] == .integer(50))
    #expect(
      try JSONDecoder().decode(CatalogDigitalObject.self, from: JSONEncoder().encode(object))
        == object)
    #expect(
      CatalogDigitalObject(source: .object(["extractedTextAccurracy": .integer(-1)]))
        .extractedTextAccuracy == -1)
    #expect(
      CatalogDigitalObject(source: .object(["extractedTextAccuracy": .integer(97)]))
        .extractedTextAccuracy == nil)
  }
}
