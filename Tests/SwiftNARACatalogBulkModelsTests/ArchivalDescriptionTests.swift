import Foundation
import SwiftNARACatalogBulkModels
import SwiftNARACatalogBulkTestSupport
import Testing

@Suite(.timeLimit(.minutes(suiteTimeLimitMinutes)))
struct ArchivalDescriptionTests {
  @Test("A fixture production date projects its exact day month year and logical date")
  func aFixtureProductionDateProjectsItsExactDayMonthYearAndLogicalDate() throws {
    let records = try Fixture.rg11.data().split(separator: 10)
    let madison = try CatalogRecord.decode(Data(records[20]))
    #expect(madison.naID == "162246501")
    let production = try #require(madison.fields["productionDates"]?.array?.first)
    let date = CatalogDate(source: production)
    #expect(date.day == 8)
    #expect(date.month == 4)
    #expect(date.year == 1816)
    #expect(date.logicalDate == "1816-04-08")
    #expect(date.source == production)
    #expect(try JSONDecoder().decode(CatalogDate.self, from: JSONEncoder().encode(date)) == date)
  }

  @Test("A year-only ancestor date keeps its logical date without day or month precision")
  func aYearOnlyAncestorDateKeepsItsLogicalDateWithoutDayOrMonthPrecision() throws {
    let records = try Fixture.rg11.data().split(separator: 10)
    let madison = try CatalogRecord.decode(Data(records[20]))
    let recordGroup = try #require(madison.ancestors?.first)
    #expect(recordGroup["naId"]?.identifier == "340")
    let start = CatalogDate(source: try #require(recordGroup["inclusiveStartDate"]))
    #expect(start.year == 1778)
    #expect(start.day == nil)
    #expect(start.month == nil)
    #expect(start.logicalDate == "1778-01-01")
    #expect(start.source["day"] == nil)
    #expect(start.source["month"] == nil)
  }

  @Test("Null and non-object date sources project nothing while remaining inspectable")
  func nullAndNonObjectDateSourcesProjectNothingWhileRemainingInspectable() {
    // Synthetic: the source supplies null instead of a date object.
    let null = CatalogDate(source: .null)
    #expect(null.day == nil && null.month == nil && null.year == nil)
    #expect(null.logicalDate == nil)
    #expect(null.source == .null)
    // Synthetic: the source supplies a string where a date object is expected.
    let string = CatalogDate(source: .string("1816-04-08"))
    #expect(string.day == nil && string.month == nil && string.year == nil)
    #expect(string.logicalDate == nil)
    #expect(string.source == .string("1816-04-08"))
  }

  @Test("Non-integer and out-of-range components are not converted")
  func nonIntegerAndOutOfRangeComponentsAreNotConverted() throws {
    // Synthetic: a fractional year, a string year, an explicit null day, and an unsigned
    // year beyond the signed range, alongside an exact integer beyond double precision.
    let date = CatalogDate(
      source: .object([
        "day": .null,
        "logicalDate": .null,
        "month": .unsignedInteger(UInt64.max),
        "year": .number(1816.5),
      ]))
    #expect(date.day == nil)
    #expect(date.month == nil)
    #expect(date.year == nil)
    #expect(date.logicalDate == nil)
    #expect(date.source["day"] == .null)
    #expect(date.source["month"] == .unsignedInteger(UInt64.max))
    #expect(date.source["year"] == .number(1816.5))
    let text = CatalogDate(source: .object(["year": .string("1816")]))
    #expect(text.year == nil)
    let decoded = try JSONDecoder().decode(
      JSONValue.self, from: Data(#"{"year":9007199254740993,"month":18446744073709551615}"#.utf8))
    let large = CatalogDate(source: decoded)
    #expect(large.year == 9_007_199_254_740_993)
    #expect(large.month == nil)
    #expect(large.source["month"] == .unsignedInteger(18_446_744_073_709_551_615))
  }

  @Test("Fixture restrictions project the exact unrestricted status without a note")
  func fixtureRestrictionsProjectTheExactUnrestrictedStatusWithoutANote() throws {
    let rg11 = try Fixture.rg11.data().split(separator: 10)
    let fdr = try Fixture.fdr.data().split(separator: 10)
    let records = [
      try CatalogRecord.decode(Data(rg11[10])), try CatalogRecord.decode(Data(fdr[1])),
    ]
    #expect(records.map(\.naID) == ["100358199", "122179401"])
    for record in records {
      for source in [record.accessRestriction, record.useRestriction] {
        let restriction = CatalogRestriction(source: try #require(source))
        #expect(restriction.source == .object(["status": .string("Unrestricted")]))
        #expect(restriction.status == .unrestricted)
        #expect(restriction.status?.rawValue == "Unrestricted")
        #expect(restriction.note == nil)
        let encoded = try JSONEncoder().encode(restriction)
        #expect(try JSONDecoder().decode(CatalogRestriction.self, from: encoded) == restriction)
      }
    }
  }

  @Test("An unknown restriction status and a note are retained exactly")
  func anUnknownRestrictionStatusAndANoteAreRetainedExactly() throws {
    // Synthetic: a status the constants do not name, a note, and a specific restriction array.
    let specific: JSONValue = .array([.object(["restriction": .string("Donor Restricted")])])
    let restriction = CatalogRestriction(
      source: .object([
        "note": .string("Register numbers 1 through 900 are open."),
        "specificAccessRestrictions": specific,
        "status": .string("Restricted - Pending Review"),
      ]))
    #expect(restriction.status == CatalogRestrictionStatus(rawValue: "Restricted - Pending Review"))
    #expect(restriction.status?.rawValue == "Restricted - Pending Review")
    #expect(restriction.status != .unrestricted)
    #expect(restriction.note == "Register numbers 1 through 900 are open.")
    #expect(restriction.source["specificAccessRestrictions"] == specific)
    let status = try #require(restriction.status)
    let encoded = String(decoding: try JSONEncoder().encode(status), as: UTF8.self)
    #expect(encoded == #""Restricted - Pending Review""#)
    let decoded = try JSONDecoder().decode(
      CatalogRestrictionStatus.self, from: Data(#""Restricted - Partly""#.utf8))
    #expect(decoded == .restrictedPartly)
    #expect(CatalogRestrictionStatus.restrictedFully.rawValue == "Restricted - Fully")
    #expect(CatalogRestrictionStatus.restrictedPossibly.rawValue == "Restricted - Possibly")
  }

  @Test("Null and wrong-shaped restriction members project nothing while remaining inspectable")
  func nullAndWrongShapedRestrictionMembersProjectNothingWhileRemainingInspectable() {
    // Synthetic: an explicit null note beside a known status.
    let nullNote = CatalogRestriction(
      source: .object(["note": .null, "status": .string("Unrestricted")]))
    #expect(nullNote.note == nil)
    #expect(nullNote.status == .unrestricted)
    #expect(nullNote.source["note"] == .null)
    // Synthetic: a numeric status and an array note.
    let wrong = CatalogRestriction(source: .object(["note": .array([]), "status": .integer(1)]))
    #expect(wrong.status == nil)
    #expect(wrong.note == nil)
    #expect(wrong.source["status"] == .integer(1))
    // Synthetic: null and a string where a restriction object is expected.
    for source: JSONValue in [.null, .string("Unrestricted")] {
      let restriction = CatalogRestriction(source: source)
      #expect(restriction.status == nil)
      #expect(restriction.note == nil)
      #expect(restriction.source == source)
    }
  }

  @Test("A record without restriction objects has no restriction to project")
  func aRecordWithoutRestrictionObjectsHasNoRestrictionToProject() throws {
    // Synthetic: a description record that omits both restriction members.
    let record = try CatalogRecord.decode(Data(#"{"record":{"naId":1}}"#.utf8))
    #expect(record.accessRestriction == nil)
    #expect(record.useRestriction == nil)
    #expect(record.accessRestriction.map(CatalogRestriction.init(source:)) == nil)
    // Synthetic: an empty restriction object.
    let empty = CatalogRestriction(source: .object([:]))
    #expect(empty.status == nil)
    #expect(empty.note == nil)
  }

  @Test("Fixture ancestors project in source order with exact identifiers and distances")
  func fixtureAncestorsProjectInSourceOrderWithExactIdentifiersAndDistances() throws {
    let records = try Fixture.rg11.data().split(separator: 10)
    let madison = try CatalogRecord.decode(Data(records[20]))
    #expect(madison.naID == "162246501")
    let sources = try #require(madison.ancestors)
    let ancestors = sources.map(CatalogAncestor.init(source:))
    #expect(ancestors.map(\.naID) == ["340", "299798", "162246305"])
    #expect(ancestors.map(\.distance) == [3, 2, 1])
    #expect(ancestors.map(\.levelOfDescription) == [.recordGroup, .series, .fileUnit])
    #expect(
      ancestors.map(\.title) == [
        "General Records of the United States Government", "Indian Treaties",
        "Ratified Indian Treaty 76: Cherokee - Washington, DC, March 22, 1816",
      ])
    #expect(ancestors.map(\.recordGroupNumber) == [11, nil, nil])
    #expect(ancestors.map(\.collectionIdentifier) == [nil, nil, nil])
    #expect(zip(ancestors, sources).allSatisfy { $0.source == $1 })
    let recordGroup = ancestors[0]
    #expect(recordGroup.inclusiveStartDate?.year == 1778)
    #expect(recordGroup.inclusiveStartDate?.logicalDate == "1778-01-01")
    #expect(recordGroup.inclusiveEndDate?.year == 2006)
    #expect(recordGroup.inclusiveEndDate?.logicalDate == "2006-01-01")
    #expect(recordGroup.creators == nil)
    let series = ancestors[1]
    #expect(series.inclusiveStartDate?.logicalDate == "1789-01-01")
    #expect(series.inclusiveEndDate?.logicalDate == "1869-01-01")
    let creator = try #require(series.creators?.first)
    #expect(series.creators?.count == 1)
    #expect(creator["heading"] == .string("U.S. Government. (03/04/1789 - )"))
    #expect(creator["naId"]?.identifier == "10468192")
    #expect(series.source["creators"] == .array([creator]))
    for ancestor in ancestors {
      let encoded = try JSONEncoder().encode(ancestor)
      #expect(try JSONDecoder().decode(CatalogAncestor.self, from: encoded) == ancestor)
    }
  }

  @Test("An ancestor without dates projects none rather than inheriting another level's dates")
  func anAncestorWithoutDatesProjectsNoneRatherThanInheritingAnotherLevelsDates() throws {
    let records = try Fixture.rg11.data().split(separator: 10)
    let madison = try CatalogRecord.decode(Data(records[20]))
    let fileUnit = CatalogAncestor(source: try #require(madison.ancestors?.last))
    #expect(fileUnit.naID == "162246305")
    #expect(fileUnit.source["inclusiveStartDate"] == nil)
    #expect(fileUnit.source["inclusiveEndDate"] == nil)
    #expect(fileUnit.inclusiveStartDate == nil)
    #expect(fileUnit.inclusiveEndDate == nil)
    #expect(madison.fields["inclusiveStartDate"] == nil)
    #expect(madison.fields["inclusiveEndDate"] == nil)
  }

  @Test("A fixture collection ancestor projects its exact collection identifier and dates")
  func aFixtureCollectionAncestorProjectsItsExactCollectionIdentifierAndDates() throws {
    let records = try Fixture.fdr.data().split(separator: 10)
    let record = try CatalogRecord.decode(Data(records[1]))
    #expect(record.naID == "122179401")
    let ancestors = try #require(record.ancestors).map(CatalogAncestor.init(source:))
    #expect(ancestors.map(\.naID) == ["577496", "577534"])
    #expect(ancestors.map(\.distance) == [2, 1])
    #expect(ancestors.map(\.levelOfDescription) == [.collection, .series])
    let collection = ancestors[0]
    #expect(collection.collectionIdentifier == "FDR-FDRMSF")
    #expect(collection.title == "Franklin D. Roosevelt Master Speech Files")
    #expect(collection.recordGroupNumber == nil)
    #expect(collection.creators == nil)
    #expect(collection.inclusiveStartDate?.day == 19)
    #expect(collection.inclusiveStartDate?.month == 1)
    #expect(collection.inclusiveStartDate?.year == 1898)
    #expect(collection.inclusiveEndDate?.logicalDate == "1945-04-13")
    #expect(ancestors[1].collectionIdentifier == nil)
    #expect(
      ancestors[1].creators?.first?["heading"]
        == .string("Roosevelt, Franklin D. (Franklin Delano), 1882-1945"))
  }

  @Test("String and large identifiers, missing distances, and unknown levels are retained exactly")
  func stringAndLargeIdentifiersMissingDistancesAndUnknownLevelsAreRetainedExactly() throws {
    // Synthetic: a string NAID with leading zeros, no distance, and a Catalog API display level.
    let display = CatalogAncestor(
      source: .object([
        "levelOfDescription": .string("Record Group"),
        "naId": .string("0000340"),
      ]))
    #expect(display.naID == "0000340")
    #expect(display.distance == nil)
    #expect(display.source["distance"] == nil)
    #expect(display.levelOfDescription == CatalogDescriptionLevel(rawValue: "Record Group"))
    #expect(display.levelOfDescription?.rawValue == "Record Group")
    #expect(display.levelOfDescription != .recordGroup)
    // Synthetic: an integer NAID beyond double precision and a level the constants do not name.
    let decoded = try JSONDecoder().decode(
      JSONValue.self,
      from: Data(#"{"levelOfDescription":"subseries","naId":9007199254740993}"#.utf8))
    let large = CatalogAncestor(source: decoded)
    #expect(large.naID == "9007199254740993")
    #expect(large.levelOfDescription?.rawValue == "subseries")
    let level = try #require(large.levelOfDescription)
    #expect(String(decoding: try JSONEncoder().encode(level), as: UTF8.self) == #""subseries""#)
    let fileUnit = try JSONDecoder().decode(
      CatalogDescriptionLevel.self, from: Data(#""fileUnit""#.utf8))
    #expect(fileUnit == .fileUnit)
    #expect(CatalogDescriptionLevel.collection.rawValue == "collection")
    #expect(CatalogDescriptionLevel.item.rawValue == "item")
    #expect(CatalogDescriptionLevel.recordGroup.rawValue == "recordGroup")
    #expect(CatalogDescriptionLevel.series.rawValue == "series")
  }

  @Test("Null and wrong-shaped ancestor members project nothing while remaining inspectable")
  func nullAndWrongShapedAncestorMembersProjectNothingWhileRemainingInspectable() {
    // Synthetic: string and fractional numbers, null dates, a string date, and object creators.
    let wrong = CatalogAncestor(
      source: .object([
        "collectionIdentifier": .integer(1),
        "creators": .object([:]),
        "distance": .string("3"),
        "inclusiveEndDate": .string("2006-12-31"),
        "inclusiveStartDate": .null,
        "levelOfDescription": .integer(1),
        "naId": .number(340.5),
        "recordGroupNumber": .number(11.5),
        "title": .null,
      ]))
    #expect(wrong.collectionIdentifier == nil)
    #expect(wrong.creators == nil)
    #expect(wrong.distance == nil)
    #expect(wrong.inclusiveEndDate == nil)
    #expect(wrong.inclusiveStartDate == nil)
    #expect(wrong.levelOfDescription == nil)
    #expect(wrong.naID == nil)
    #expect(wrong.recordGroupNumber == nil)
    #expect(wrong.title == nil)
    #expect(wrong.source["distance"] == .string("3"))
    #expect(wrong.source["inclusiveEndDate"] == .string("2006-12-31"))
    #expect(wrong.source["inclusiveStartDate"] == .null)
    #expect(wrong.source["recordGroupNumber"] == .number(11.5))
    // Synthetic: null and a string where an ancestor object is expected.
    for source: JSONValue in [.null, .string("340")] {
      let ancestor = CatalogAncestor(source: source)
      #expect(ancestor.naID == nil)
      #expect(ancestor.distance == nil)
      #expect(ancestor.levelOfDescription == nil)
      #expect(ancestor.title == nil)
      #expect(ancestor.source == source)
    }
  }

  @Test("A fixture item description projects its title, level, dates, hierarchy, and restrictions")
  func aFixtureItemDescriptionProjectsItsTitleLevelDatesHierarchyAndRestrictions() throws {
    let records = try Fixture.rg11.data().split(separator: 10)
    let record = try CatalogRecord.decode(Data(records[20]))
    let description = try #require(record.archivalDescription)
    #expect(description.source == record.fields)
    #expect(description.naID == "162246501")
    #expect(description.recordType == "description")
    #expect(description.levelOfDescription == .item)
    #expect(
      description.title
        == "Instrument of Ratification Signed by President James Madison and Secretary of State James Monroe"
    )
    #expect(description.generalRecordsTypes == ["Textual Records"])
    #expect(description.scopeAndContentNote == nil)
    let production = try #require(description.productionDates)
    #expect(production.map(\.logicalDate) == ["1816-04-08"])
    #expect(production.map(\.day) == [8])
    #expect(production.map(\.month) == [4])
    #expect(production.map(\.year) == [1816])
    #expect(description.inclusiveStartDate == nil)
    #expect(description.inclusiveEndDate == nil)
    let ancestors = try #require(description.ancestors)
    #expect(ancestors.map(\.naID) == ["340", "299798", "162246305"])
    #expect(ancestors.map(\.distance) == [3, 2, 1])
    #expect(ancestors.map(\.levelOfDescription) == [.recordGroup, .series, .fileUnit])
    #expect(ancestors.map(\.source) == record.ancestors)
    #expect(description.accessRestriction?.status == .unrestricted)
    #expect(description.useRestriction?.status == .unrestricted)
    #expect(description.accessRestriction?.source == record.accessRestriction)
    #expect(description.useRestriction?.source == record.useRestriction)
    let occurrences = try #require(description.physicalOccurrences)
    #expect(occurrences.count == 1)
    #expect(occurrences[0]["copyStatus"] == .string("Preservation"))
    #expect(
      occurrences[0]["mediaOccurrences"]?.array?[0]["physicalRestrictionNote"]
        == .string(
          "This item is located in a specially protected area and is not pulled for use in the Central Research Room."
        ))
    #expect(record.naID == "162246501")
    #expect(record.levelOfDescription == "item")
    #expect(record.digitalObjects?.count == 9)
    let encoded = try JSONEncoder().encode(description)
    #expect(try JSONDecoder().decode(CatalogDescription.self, from: encoded) == description)
  }

  @Test("A second fixture item description keeps its own production date and file unit")
  func aSecondFixtureItemDescriptionKeepsItsOwnProductionDateAndFileUnit() throws {
    let records = try Fixture.rg11.data().split(separator: 10)
    let record = try CatalogRecord.decode(Data(records[10]))
    let description = try #require(record.archivalDescription)
    #expect(description.naID == "100358199")
    #expect(description.levelOfDescription == .item)
    #expect(
      description.title
        == "Instrument of Ratification Signed by President James Monroe and Secretary of State John Quincy Adams"
    )
    let production = try #require(description.productionDates?.first)
    #expect(description.productionDates?.count == 1)
    #expect(production.day == 26)
    #expect(production.month == 12)
    #expect(production.year == 1817)
    #expect(production.logicalDate == "1817-12-26")
    #expect(description.ancestors?.map(\.naID) == ["340", "299798", "100311143"])
    #expect(description.ancestors?.map(\.distance) == [3, 2, 1])
    #expect(description.accessRestriction?.status == .unrestricted)
    #expect(description.accessRestriction?.note == nil)
    #expect(description.useRestriction?.status == .unrestricted)
    #expect(
      description.physicalOccurrences?[0]["mediaOccurrences"]?.array?[0]["physicalRestrictionNote"]
        == .string(
          "This item is located in a specially protected area and is not pulled for use in the Central Research Room."
        ))
  }

  @Test(
    "Fixture file unit descriptions project their collection hierarchy without production dates")
  func fixtureFileUnitDescriptionsProjectTheirCollectionHierarchyWithoutProductionDates() throws {
    let records = try Fixture.fdr.data().split(separator: 10)
    let savannah = try CatalogRecord.decode(Data(records[1]))
    let verse = try CatalogRecord.decode(Data(records[3]))
    let descriptions = [
      try #require(savannah.archivalDescription), try #require(verse.archivalDescription),
    ]
    #expect(descriptions.map(\.naID) == ["122179401", "122197642"])
    #expect(
      descriptions.map(\.title) == [
        "Savannah, Georgia - Georgia Bicentennial (Speech File 660) of November 18, 1933",
        "Humorous Verse of the President to the Three Press Associations (Speech File 1457) of March 19, 1943",
      ])
    #expect(descriptions.map(\.levelOfDescription) == [.fileUnit, .fileUnit])
    #expect(
      descriptions.map { $0.physicalOccurrences?[0]["mediaOccurrences"]?.array?[0]["containerId"] }
        == [.string("Original Box #16, Folder #8"), .string("Original Box #71, Folder #14")])
    #expect(savannah.digitalObjects?.count == 25)
    #expect(verse.digitalObjects?.count == 4)
    for description in descriptions {
      #expect(description.recordType == "description")
      #expect(description.productionDates == nil)
      #expect(description.source["productionDates"] == nil)
      #expect(description.inclusiveStartDate == nil)
      #expect(description.inclusiveEndDate == nil)
      #expect(description.scopeAndContentNote == nil)
      #expect(description.generalRecordsTypes == ["Textual Records"])
      #expect(description.ancestors?.map(\.naID) == ["577496", "577534"])
      #expect(description.ancestors?.map(\.levelOfDescription) == [.collection, .series])
      #expect(description.ancestors?.first?.collectionIdentifier == "FDR-FDRMSF")
      #expect(description.accessRestriction?.status == .unrestricted)
      #expect(description.useRestriction?.status == .unrestricted)
      #expect(
        description.physicalOccurrences?[0]["mediaOccurrences"]?.array?[0][
          "physicalRestrictionNote"]
          == nil)
    }
  }

  @Test("A description without declared digital objects still projects")
  func aDescriptionWithoutDeclaredDigitalObjectsStillProjects() throws {
    let records = try Fixture.fdr.data().split(separator: 10)
    let record = try CatalogRecord.decode(Data(records[5]))
    let description = try #require(record.archivalDescription)
    #expect(description.naID == "122205923")
    #expect(
      description.title
        == "Message to Congress re Hospital Construction (Speech File 1271) of January 31, 1940")
    #expect(description.levelOfDescription == .fileUnit)
    #expect(description.ancestors?.map(\.naID) == ["577496", "577534"])
    #expect(record.fields["digitalObjects"] == nil)
    #expect(record.digitalObjects == nil)
    #expect(record.isMetadataOnly == nil)
  }

  @Test("Every fixture record is a description and omitted members stay absent")
  func everyFixtureRecordIsADescriptionAndOmittedMembersStayAbsent() throws {
    let rg11 = try Fixture.rg11.data().split(separator: 10).map {
      try CatalogRecord.decode(Data($0))
    }
    let fdr = try Fixture.fdr.data().split(separator: 10).map {
      try CatalogRecord.decode(Data($0))
    }
    #expect(rg11.count == 35)
    #expect(fdr.count == 7)
    let descriptions = (rg11 + fdr).compactMap(\.archivalDescription)
    #expect(descriptions.count == 42)
    #expect(descriptions.filter { $0.productionDates != nil }.count == 23)
    #expect(descriptions.filter { $0.inclusiveStartDate != nil }.count == 0)
    let scoped = descriptions.filter { $0.scopeAndContentNote != nil }
    #expect(scoped.map(\.naID) == ["299953", "210835707"])
    let pacific = try #require(scoped.first?.scopeAndContentNote)
    #expect(
      pacific.hasPrefix(
        "This item is the Pacific Railway Act which which designated the 32nd parallel as"))
  }

  @Test("Only an exact description record type produces an archival description")
  func onlyAnExactDescriptionRecordTypeProducesAnArchivalDescription() throws {
    // Synthetic: the documented authority, contribution, and delete types, an unknown type, a
    // different spelling, null, a number, and an omitted type.
    let members = [
      #""recordType":"authority","#, #""recordType":"contribution","#, #""recordType":"delete","#,
      #""recordType":"futureRecordType","#, #""recordType":"Description","#,
      #""recordType":null,"#, #""recordType":1,"#, "",
    ]
    for member in members {
      let record = try CatalogRecord.decode(
        Data((#"{"record":{"naId":1,"# + member + #""title":"Synthetic"}}"#).utf8))
      #expect(record.archivalDescription == nil)
      #expect(record.naID == "1")
      #expect(record.title == "Synthetic")
    }
    let unknown = try CatalogRecord.decode(
      Data(#"{"record":{"naId":1,"recordType":"futureRecordType","title":"Synthetic"}}"#.utf8))
    #expect(unknown.fields["recordType"] == .string("futureRecordType"))
    // Synthetic: the smallest envelope with the description type.
    let minimal = try CatalogRecord.decode(
      Data(#"{"record":{"naId":1,"recordType":"description"}}"#.utf8))
    let description = try #require(minimal.archivalDescription)
    #expect(description.naID == "1")
    #expect(description.recordType == "description")
    #expect(description.title == nil)
    #expect(description.ancestors == nil)
  }

  @Test("Projecting a description leaves the line bytes and envelope intact")
  func projectingADescriptionLeavesTheLineBytesAndEnvelopeIntact() throws {
    let data = try Fixture.rg11.data()
    let raw = data.subdata(in: 358_605..<375_909)
    #expect(raw.count == 17_304)
    #expect(raw.last == 10)
    let record = try CatalogRecord.decode(raw)
    let receipt = ShardReceipt(
      byteCount: 417_823, fileURL: URL(filePath: "/shards/rg_11-1.jsonl"),
      retrieval: SourceRetrieval(
        headers: [], retrievedAt: Date(timeIntervalSince1970: 1234), status: 200,
        url: try #require(
          URL(
            string:
              "https://nara-national-archives-catalog.s3.amazonaws.com/descriptions/record-groups/rg_11/rg_11-1.jsonl"
          ))))
    let line = CatalogLine(
      byteOffset: 358_605, lineNumber: 21, rawBytes: raw, record: record, shard: receipt)
    let description = try #require(line.record.archivalDescription)
    #expect(description.naID == "162246501")
    #expect(line.rawBytes == data.subdata(in: 358_605..<375_909))
    #expect(line.record.fields == description.source)
    let decoded = try CatalogRecord.decode(JSONEncoder().encode(line.record))
    #expect(decoded == line.record)
    #expect(decoded.archivalDescription == description)
    #expect(decoded.ancestors == record.ancestors)
    #expect(decoded.accessRestriction == record.accessRestriction)
    #expect(line.rawBytes == raw)
  }

  @Test("Record-level inclusive dates project only the description's own date objects")
  func recordLevelInclusiveDatesProjectOnlyTheDescriptionsOwnDateObjects() throws {
    // Synthetic: a series with its own inclusive dates, which the Catalog schema documents for
    // record groups, collections, and series; no recorded fixture record carries them.
    let series = try CatalogRecord.decode(
      Data(
        #"{"record":{"ancestors":[{"distance":1,"inclusiveEndDate":{"logicalDate":"2006-12-31","year":2006},"inclusiveStartDate":{"logicalDate":"1778-01-01","year":1778},"levelOfDescription":"recordGroup","naId":340}],"inclusiveEndDate":{"logicalDate":"1869-01-01","year":1869},"inclusiveStartDate":{"day":4,"logicalDate":"1789-03-04","month":3,"year":1789},"levelOfDescription":"series","naId":299798,"recordType":"description"}}"#
          .utf8))
    let description = try #require(series.archivalDescription)
    #expect(description.levelOfDescription == .series)
    let start = try #require(description.inclusiveStartDate)
    #expect(start.day == 4)
    #expect(start.month == 3)
    #expect(start.year == 1789)
    #expect(start.logicalDate == "1789-03-04")
    let end = try #require(description.inclusiveEndDate)
    #expect(end.year == 1869)
    #expect(end.day == nil)
    #expect(end.month == nil)
    #expect(end.logicalDate == "1869-01-01")
    #expect(description.ancestors?.first?.inclusiveEndDate?.logicalDate == "2006-12-31")
    // Synthetic: a child without its own dates beneath the same dated ancestor.
    let child = try CatalogRecord.decode(
      Data(
        #"{"record":{"ancestors":[{"distance":1,"inclusiveEndDate":{"logicalDate":"2006-12-31","year":2006},"levelOfDescription":"recordGroup","naId":340}],"naId":1,"recordType":"description"}}"#
          .utf8))
    let undated = try #require(child.archivalDescription)
    #expect(undated.inclusiveStartDate == nil)
    #expect(undated.inclusiveEndDate == nil)
    #expect(undated.productionDates == nil)
    #expect(undated.ancestors?.first?.inclusiveEndDate?.year == 2006)
  }

  @Test("Null and wrong-shaped description members project nothing while remaining inspectable")
  func nullAndWrongShapedDescriptionMembersProjectNothingWhileRemainingInspectable() throws {
    // Synthetic: every projected member in a shape the projections do not accept.
    let wrong = CatalogDescription(
      source: .object([
        "accessRestriction": .string("Unrestricted"),
        "ancestors": .object([:]),
        "generalRecordsTypes": .array([.string("Textual Records"), .integer(1)]),
        "inclusiveEndDate": .string("1869"),
        "inclusiveStartDate": .null,
        "levelOfDescription": .null,
        "naId": .number(1.5),
        "physicalOccurrences": .object([:]),
        "productionDates": .object(["year": .integer(1816)]),
        "recordType": .integer(1),
        "scopeAndContentNote": .array([]),
        "title": .integer(1),
        "useRestriction": .null,
      ]))
    #expect(wrong.accessRestriction == nil)
    #expect(wrong.ancestors == nil)
    #expect(wrong.generalRecordsTypes == nil)
    #expect(wrong.inclusiveEndDate == nil)
    #expect(wrong.inclusiveStartDate == nil)
    #expect(wrong.levelOfDescription == nil)
    #expect(wrong.naID == nil)
    #expect(wrong.physicalOccurrences == nil)
    #expect(wrong.productionDates == nil)
    #expect(wrong.recordType == nil)
    #expect(wrong.scopeAndContentNote == nil)
    #expect(wrong.title == nil)
    #expect(wrong.useRestriction == nil)
    #expect(
      wrong.source["generalRecordsTypes"] == .array([.string("Textual Records"), .integer(1)]))
    #expect(wrong.source["productionDates"] == .object(["year": .integer(1816)]))
    #expect(wrong.source["useRestriction"] == .null)
    // Synthetic: arrays keep every element in position, including non-object elements.
    let mixed = CatalogDescription(
      source: .object([
        "ancestors": .array([.null, .object(["naId": .integer(340)])]),
        "generalRecordsTypes": .array([]),
        "productionDates": .array([.string("1816"), .object(["year": .integer(1816)])]),
      ]))
    #expect(mixed.ancestors?.map(\.naID) == [nil, "340"])
    #expect(mixed.ancestors?.first?.source == .null)
    #expect(mixed.productionDates?.map(\.year) == [nil, 1816])
    #expect(mixed.productionDates?.first?.source == .string("1816"))
    #expect(mixed.generalRecordsTypes == [])
    // Synthetic: an integer NAID beyond double precision and a level the constants do not name.
    let decoded = try JSONDecoder().decode(
      JSONValue.self,
      from: Data(
        #"{"levelOfDescription":"subseries","naId":9007199254740993,"recordType":"description"}"#
          .utf8))
    let large = CatalogDescription(source: decoded)
    #expect(large.naID == "9007199254740993")
    #expect(large.levelOfDescription?.rawValue == "subseries")
    // Synthetic: null and a string where a record object is expected.
    for source: JSONValue in [.null, .string("description")] {
      let description = CatalogDescription(source: source)
      #expect(description.naID == nil)
      #expect(description.recordType == nil)
      #expect(description.title == nil)
      #expect(description.ancestors == nil)
      #expect(description.source == source)
    }
  }
}
