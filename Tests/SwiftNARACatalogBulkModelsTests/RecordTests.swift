import Foundation
import SwiftNARACatalogBulkModels
import SwiftNARACatalogBulkTestSupport
import Testing

@Suite(.timeLimit(.minutes(suiteTimeLimitMinutes)))
struct RecordTests {
  @Test("Historical records preserve hierarchy dates rights and OCR")
  func historicalRecordsPreserveHierarchyDatesRightsAndOCR() throws {
    let records = try Fixture.rg11.data().split(separator: 10)
    #expect(records.count == 35)
    let madison = try CatalogRecord.decode(Data(records[20]))
    #expect(madison.naID == "162246501")
    let monroe = try CatalogRecord.decode(Data(records[10]))
    #expect(monroe.naID == "100358199")
    #expect(
      madison.fields["productionDates"]?.array?.first?["logicalDate"] == .string("1816-04-08"))
    #expect(monroe.fields["productionDates"]?.array?.first?["logicalDate"] == .string("1817-12-26"))
    #expect(madison.digitalObjects?.count == 9)
    #expect(monroe.digitalObjects?.count == 7)
    #expect(madison.ancestors?.first?["naId"]?.identifier == "340")
    #expect(monroe.accessRestriction?["status"] == .string("Unrestricted"))
    #expect(monroe.useRestriction?["status"] == .string("Unrestricted"))
    let fdr = try Fixture.fdr.data().split(separator: 10)
    #expect(fdr.count == 7)
    let speech = try CatalogRecord.decode(Data(fdr[1]))
    #expect(speech.naID == "122179401")
    #expect(speech.digitalObjects?.count == 25)
    #expect(speech.digitalObjects?.first?.extractedText?.contains("Franklin D. Roosevelt") == true)
    let historical = try CatalogRecord.decode(Data(fdr[3]))
    let campaign = try CatalogRecord.decode(Data(fdr[2]))
    #expect(historical.naID == "122197642" && historical.title?.contains("1943") == true)
    #expect(campaign.naID == "122185893" && campaign.title?.contains("Campaign") == true)
    let metadata = try CatalogRecord.decode(Data(fdr[5]))
    #expect(metadata.naID == "122205923")
    #expect(metadata.digitalObjects == nil)
    #expect(metadata.fields["digitalObjects"] == nil)
    #expect(metadata.isMetadataOnly == nil)
  }

  @Test("Null unknown fields and exact integer identifiers survive decoding")
  func nullUnknownFieldsAndExactIntegerIdentifiersSurviveDecoding() throws {
    let data = Data(
      #"{"future":null,"record":{"naId":9007199254740993,"title":null,"ancestors":[{"naId":"unknown","distance":7}],"digitalObjects":[],"useRestriction":{"status":"Future restriction","note":null},"newField":{"value":true}}}"#
        .utf8)
    let record = try CatalogRecord.decode(data)
    #expect(record.naID == "9007199254740993")
    #expect(record.source["future"] == .null)
    #expect(record.fields["title"] == .null)
    #expect(record.fields["missing"] == nil)
    #expect(record.useRestriction?["status"] == .string("Future restriction"))
    #expect(
      try JSONDecoder().decode(CatalogRecord.self, from: JSONEncoder().encode(record)) == record)
    #expect(throws: CatalogDecodingError.malformedJSON) {
      try CatalogRecord.decode(Data(#"{"record":{}}"#.utf8))
    }
    #expect(throws: CatalogDecodingError.limitExceeded) {
      try CatalogRecord.decode(data, maximumBytes: 2)
    }
    let absent = try CatalogRecord.decode(Data(#"{"record":{"naId":"42"}}"#.utf8))
    #expect(absent.isMetadataOnly == nil)
  }
}
