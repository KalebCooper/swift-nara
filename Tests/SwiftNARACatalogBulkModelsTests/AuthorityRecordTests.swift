import Foundation
import SwiftNARACatalogBulkModels
import SwiftNARACatalogBulkTestSupport
import Testing

@Suite(.timeLimit(.minutes(suiteTimeLimitMinutes)))
struct AuthorityRecordTests {
  @Test("Every authority fixture record projects as an authority and never as a description")
  func everyAuthorityFixtureRecordProjectsAsAnAuthorityAndNeverAsADescription() throws {
    let expectations: [(Fixture, Int, String, CatalogAuthorityType)] = [
      (.geographicReference, 32, "485327416", .geographicPlaceName),
      (.organization, 156, "486117330", .organization),
      (.person, 125, "470787114", .person),
      (.specificRecordsType, 2, "539925846", .specificRecordsType),
      (.topicalSubject, 54, "10636684", .topicalSubject),
    ]
    for (fixture, count, firstNAID, type) in expectations {
      let records = try Self.records(fixture)
      #expect(records.count == count)
      let authorities = records.compactMap(\.authorityRecord)
      #expect(authorities.count == count)
      #expect(authorities.first?.naID == firstNAID)
      #expect(authorities.allSatisfy { $0.authorityType == type })
      #expect(authorities.allSatisfy { $0.recordType == "authority" })
      #expect(authorities.allSatisfy { $0.heading != nil })
      #expect(records.allSatisfy { $0.archivalDescription == nil })
      #expect(records.allSatisfy { $0.title == nil && $0.levelOfDescription == nil })
    }
  }

  @Test("Description fixture records have no authority record")
  func descriptionFixtureRecordsHaveNoAuthorityRecord() throws {
    let records = try Self.records(.rg11) + Self.records(.fdr)
    #expect(records.count == 42)
    #expect(records.allSatisfy { $0.authorityRecord == nil })
    #expect(records.allSatisfy { $0.archivalDescription != nil })
  }

  @Test("Fixture geographic place names project headings, notes, and references")
  func fixtureGeographicPlaceNamesProjectHeadingsNotesAndReferences() throws {
    let records = try Self.records(.geographicReference)
    let tehran = try #require(records[0].authorityRecord)
    #expect(tehran.naID == "485327416")
    #expect(tehran.heading == "Tehran Province (Iran)")
    #expect(tehran.isPreferred == false)
    #expect(tehran.sourceNotes == nil)
    #expect(tehran.organizationalReferences == nil)
    #expect(tehran.source["linkCounts"]?["jurisdiction"] == .integer(1))

    let ionia = try #require(records[1].authorityRecord)
    #expect(ionia.naID == "10036426")
    #expect(ionia.heading == "Ionia County (Mich.)")
    #expect(ionia.isPreferred == true)
    #expect(ionia.sourceNotes == ["LC authorities online."])
    #expect(ionia.source["coordinates"] == .string("42 57 N, 085 04 W (42.95, -85.067)"))
    let reference = try #require(ionia.organizationalReferences?.first)
    #expect(ionia.organizationalReferences?.count == 1)
    #expect(reference.naID == "10578653")
    #expect(
      reference.heading
        == "Department of the Treasury. Office of the Commissioner of Internal Revenue. Michigan Collection District 4. (09/17/1862 - 08/07/1883)"
    )

    let veracruz = try #require(records[6].authorityRecord)
    #expect(veracruz.naID == "10037262")
    #expect(veracruz.heading == "Veracruz (Veracruz-Llave, Mexico)")
    let scope = try #require(veracruz.scopeNote)
    #expect(scope.hasPrefix("First Mexican municipality; moved to present site 1599;"))
  }

  @Test("Fixture organizations project history notes, raw names, and typed references")
  func fixtureOrganizationsProjectHistoryNotesRawNamesAndTypedReferences() throws {
    let records = try Self.records(.organization)
    let hispanics = try #require(records[0].authorityRecord)
    #expect(hispanics.naID == "486117330")
    #expect(hispanics.isPreferred == false)
    let heading = try #require(hispanics.heading)
    #expect(
      heading.hasPrefix(
        "Department of Education. Office of the Deputy Secretary. White House Initiative"))
    let history = try #require(hispanics.administrativeHistoryNote)
    #expect(history.hasPrefix("On October 19, 2010, Executive Order 13555 established"))
    let names = try #require(hispanics.organizationNames)
    #expect(names.count == 2)
    #expect(names[0]["naId"] == .integer(486_117_331))
    #expect(names[1]["naId"] == .integer(486_117_332))
    #expect(names[0]["abolishDate"]?["logicalDate"] == .string("2011-12-31"))
    #expect(names[0]["abolishDate"]?["month"] == nil)

    let fourthService = try #require(records[34].authorityRecord)
    #expect(fourthService.naID == "10533962")
    let jurisdictions = try #require(fourthService.jurisdictions)
    #expect(
      jurisdictions.compactMap(\.naID) == [
        "10045240", "10045339", "10045327", "10044371", "10045172", "10045287", "10045286",
      ])
    #expect(
      jurisdictions.compactMap(\.heading) == [
        "Mississippi", "South Carolina", "North Carolina", "Alabama", "Tennessee", "Georgia",
        "Florida",
      ])

    let personal = try #require(records[35].authorityRecord?.personalReferences)
    #expect(records[35].naID == "10534110")
    #expect(personal.count == 1)
    #expect(personal[0].naID == "10679523")
    #expect(personal[0].heading == "Goldberg, Arthur J. (Arthur Joseph), 1908-1990")
  }

  @Test("Fixture organizations without a preferred flag project nil rather than false")
  func fixtureOrganizationsWithoutAPreferredFlagProjectNilRatherThanFalse() throws {
    let authorities = try Self.records(.organization).compactMap(\.authorityRecord)
    let unflagged = authorities.filter { $0.isPreferred == nil }
    #expect(unflagged.compactMap(\.naID) == ["10521685", "10522004", "10522724", "10523941"])
    #expect(unflagged.allSatisfy { $0.source["preferred"] == nil })
    let first = try #require(unflagged.first)
    #expect(first.heading == "964778")
    #expect(first.sourceNotes == ["CREATED FROM LCNAF CONVERSION"])
  }

  @Test("Fixture persons project names, notes, and dates with only their source components")
  func fixturePersonsProjectNamesNotesAndDatesWithOnlyTheirSourceComponents() throws {
    let records = try Self.records(.person)
    let aaron = try #require(records[0].authorityRecord)
    #expect(aaron.naID == "470787114")
    #expect(aaron.heading == "Aaron, David L., 1938-")
    #expect(aaron.name == "Aaron, David L.,")
    #expect(aaron.isPreferred == false)
    let birth = try #require(aaron.birthDate)
    #expect(birth.year == 1938)
    #expect(birth.month == 8)
    #expect(birth.day == nil)
    #expect(birth.logicalDate == "1938-08-21")
    #expect(aaron.deathDate == nil)
    #expect(aaron.biographicalNote == nil)
    #expect(aaron.source["role"]?["creator"] == .bool(false))

    let synar = try #require(records[10].authorityRecord)
    #expect(synar.naID == "10570108")
    #expect(synar.heading == "Synar, Mike, 1950-1996")
    #expect(synar.isPreferred == true)
    let note = try #require(synar.biographicalNote)
    #expect(note.hasPrefix("Mike Synar (b. Oct. 17, 1950, Vinita, Ok.-d. Jan. 9, 1996,"))
    let born = try #require(synar.birthDate)
    #expect(born.year == 1950)
    #expect(born.month == nil)
    #expect(born.day == nil)
    #expect(born.logicalDate == "1950-01-01")
    let died = try #require(synar.deathDate)
    #expect(died.year == 1996)
    #expect(died.month == nil)
    #expect(died.day == nil)
    #expect(died.logicalDate == "1996-12-31")
    #expect(synar.sourceNotes?.count == 3)
    #expect(synar.organizationalReferences?.first?.naID == "10544098")
    let variants = try #require(synar.variantPersonNames)
    #expect(variants.count == 1)
    #expect(variants[0]["heading"] == .string("Synar, Michael L., 1950-1996"))

    let authorities = records.compactMap(\.authorityRecord)
    #expect(authorities.filter { $0.birthDate != nil }.count == 74)
    #expect(authorities.filter { $0.deathDate != nil }.count == 53)
  }

  @Test("Fixture subject and records type terms keep their relation kinds in source order")
  func fixtureSubjectAndRecordsTypeTermsKeepTheirRelationKindsInSourceOrder() throws {
    let topical = try Self.records(.topicalSubject)
    let privilege = try #require(topical[0].authorityRecord)
    #expect(privilege.heading == "Executive privilege (Government information)")
    #expect(privilege.isPreferred == true)
    #expect(
      privilege.broaderTerms?.compactMap(\.naID) == [
        "10638098", "10640306", "10641520", "10636683", "10642747", "10637276",
      ])
    #expect(privilege.broaderTerms?.first?.heading == "Freedom of information")
    #expect(privilege.narrowerTerms == nil)
    #expect(
      privilege.useFor == [
        "Legislative right to information from executive agencies", "Secrecy in government",
        "Government secrecy",
      ])
    #expect(privilege.sourceNotes == ["OCLC authority file. | DE800."])

    let handicraft = try #require(topical[2].authorityRecord)
    #expect(handicraft.naID == "10637839")
    #expect(handicraft.broaderTerms?.compactMap(\.naID) == ["10641201"])
    #expect(
      handicraft.narrowerTerms?.compactMap(\.heading) == [
        "Wreaths", "Hobbies", "Miniature craft", "Models and modelmaking", "Indian craft",
      ])
    #expect(handicraft.relatedTerms?.compactMap(\.naID) == ["10641203", "10643574"])

    let recordsTypes = try Self.records(.specificRecordsType).compactMap(\.authorityRecord)
    #expect(recordsTypes[0].heading == "Public interest advertising")
    #expect(recordsTypes[0].broaderTerms == nil)
    #expect(recordsTypes[1].naID == "10635591")
    #expect(recordsTypes[1].heading == "Laboratory notes")
    #expect(recordsTypes[1].broaderTerms?.first?.heading == "Notes")
  }

  @Test("A reference to a record absent from every fixture keeps its exact identifier")
  func aReferenceToARecordAbsentFromEveryFixtureKeepsItsExactIdentifier() throws {
    var identifiers: Set<String> = []
    for fixture in [
      Fixture.geographicReference, .organization, .person, .specificRecordsType, .topicalSubject,
    ] {
      identifiers.formUnion(try Self.records(fixture).map(\.naID))
    }
    #expect(identifiers.count == 369)
    let laboratory = try #require(Self.records(.specificRecordsType)[1].authorityRecord)
    let broader = try #require(laboratory.broaderTerms?.first)
    #expect(broader.naID == "10635584")
    #expect(broader.source["naId"] == .integer(10_635_584))
    #expect(!identifiers.contains("10635584"))
  }

  @Test("An unknown authority type and a display spelling are retained exactly")
  func anUnknownAuthorityTypeAndADisplaySpellingAreRetainedExactly() throws {
    // Synthetic: a type no recorded export contains, and the Catalog API display spelling.
    let unknown = try Self.authority(#""authorityType":"futureAuthority""#)
    #expect(unknown.authorityType?.rawValue == "futureAuthority")
    #expect(unknown.authorityType != .person)
    let display = try Self.authority(#""authorityType":"Topical Subject""#)
    #expect(display.authorityType?.rawValue == "Topical Subject")
    #expect(display.authorityType != .topicalSubject)
    let type = CatalogAuthorityType(rawValue: "geographicPlaceName")
    #expect(type == .geographicPlaceName)
    #expect(
      try JSONDecoder().decode(CatalogAuthorityType.self, from: JSONEncoder().encode(type)) == type)
  }

  @Test("Synthetic partial and malformed dates project only exact source components")
  func syntheticPartialAndMalformedDatesProjectOnlyExactSourceComponents() throws {
    // Synthetic: a year-only birth date without a logical date and a string death date.
    let partial = try Self.authority(#""birthDate":{"year":1901},"deathDate":"1990-05-01""#)
    let birth = try #require(partial.birthDate)
    #expect(birth.year == 1901)
    #expect(birth.month == nil && birth.day == nil && birth.logicalDate == nil)
    #expect(partial.deathDate == nil)
    #expect(partial.source["deathDate"] == .string("1990-05-01"))
    // Synthetic: an explicit null birth date and a fractional death year.
    let odd = try Self.authority(#""birthDate":null,"deathDate":{"year":1990.5}"#)
    #expect(odd.birthDate == nil)
    #expect(odd.source["birthDate"] == .null)
    #expect(odd.deathDate?.year == nil)
  }

  @Test("Null and wrong-shaped authority members project nothing while remaining inspectable")
  func nullAndWrongShapedAuthorityMembersProjectNothingWhileRemainingInspectable() throws {
    // Synthetic: every projected member supplied as null or with an unexpected shape.
    let record = try Self.authority(
      #""administrativeHistoryNote":1,"authorityType":null,"biographicalNote":[],"#
        + #""broaderTerms":{},"heading":null,"jurisdictions":"Ohio","name":false,"#
        + #""organizationNames":{},"preferred":"true","scopeNote":null,"#
        + #""sourceNotes":["A note",2],"useFor":null,"variantPersonNames":"Smith""#)
    #expect(record.administrativeHistoryNote == nil)
    #expect(record.authorityType == nil)
    #expect(record.biographicalNote == nil)
    #expect(record.broaderTerms == nil)
    #expect(record.heading == nil)
    #expect(record.isPreferred == nil)
    #expect(record.jurisdictions == nil)
    #expect(record.name == nil)
    #expect(record.organizationNames == nil)
    #expect(record.scopeNote == nil)
    #expect(record.sourceNotes == nil)
    #expect(record.useFor == nil)
    #expect(record.variantPersonNames == nil)
    #expect(record.source["preferred"] == .string("true"))
    #expect(record.source["sourceNotes"] == .array([.string("A note"), .integer(2)]))
    #expect(record.naID == "1")
    // Synthetic: a non-object record projects every member as nil.
    let string = CatalogAuthorityRecord(source: .string("authority"))
    #expect(string.naID == nil && string.heading == nil && string.isPreferred == nil)
    #expect(string.source == .string("authority"))
  }

  @Test("Reference elements keep their positions, exact identifiers, and raw shapes")
  func referenceElementsKeepTheirPositionsExactIdentifiersAndRawShapes() throws {
    // Synthetic: a string identifier, an integer beyond double precision, a duplicate, a
    // reference without a heading, and a non-object element.
    let record = try Self.authority(
      #""relatedTerms":[{"heading":"A","naId":"0042"},{"naId":9007199254740993},"#
        + #"{"heading":"A","naId":"0042"},"Loose term",{"heading":7,"naId":1.5}]"#)
    let terms = try #require(record.relatedTerms)
    #expect(terms.count == 5)
    #expect(terms[0].naID == "0042")
    #expect(terms[0].heading == "A")
    #expect(terms[1].naID == "9007199254740993")
    #expect(terms[1].heading == nil)
    #expect(terms[2] == terms[0])
    #expect(terms[3].naID == nil && terms[3].heading == nil)
    #expect(terms[3].source == .string("Loose term"))
    #expect(terms[4].naID == nil && terms[4].heading == nil)
    #expect(terms[4].source["naId"] == .number(1.5))
  }

  @Test("Only an exact authority record type produces an authority record")
  func onlyAnExactAuthorityRecordTypeProducesAnAuthorityRecord() throws {
    // Synthetic: the description type, an unknown type, a different spelling, null, a number,
    // and an omitted type.
    let members = [
      #""recordType":"description","#, #""recordType":"futureRecordType","#,
      #""recordType":"Authority","#, #""recordType":null,"#, #""recordType":1,"#, "",
    ]
    for member in members {
      let record = try CatalogRecord.decode(
        Data((#"{"record":{"naId":1,"# + member + #""heading":"Synthetic"}}"#).utf8))
      #expect(record.authorityRecord == nil)
      #expect(record.naID == "1")
      #expect(record.fields["heading"] == .string("Synthetic"))
    }
    let unknown = try CatalogRecord.decode(
      Data(#"{"record":{"naId":1,"recordType":"futureRecordType"}}"#.utf8))
    #expect(unknown.archivalDescription == nil)
    #expect(unknown.authorityRecord == nil)
    #expect(unknown.fields["recordType"] == .string("futureRecordType"))
    // Synthetic: the smallest envelope with the authority type, without a title or level.
    let minimal = try CatalogRecord.decode(
      Data(#"{"record":{"naId":1,"recordType":"authority"}}"#.utf8))
    let authority = try #require(minimal.authorityRecord)
    #expect(minimal.archivalDescription == nil)
    #expect(minimal.title == nil && minimal.levelOfDescription == nil)
    #expect(authority.naID == "1")
    #expect(authority.recordType == "authority")
    #expect(authority.heading == nil && authority.authorityType == nil)
  }

  @Test("Projecting an authority leaves the line bytes and envelope intact")
  func projectingAnAuthorityLeavesTheLineBytesAndEnvelopeIntact() throws {
    let data = try Fixture.topicalSubject.data()
    let lines = data.split(separator: 10, omittingEmptySubsequences: false)
    let raw = Data(lines[0]) + Data([10])
    let record = try CatalogRecord.decode(raw)
    let authority = try #require(record.authorityRecord)
    #expect(authority.naID == "10636684")
    #expect(record.fields == authority.source)
    #expect(data.prefix(raw.count) == raw)
    let decoded = try CatalogRecord.decode(JSONEncoder().encode(record))
    #expect(decoded == record)
    #expect(decoded.authorityRecord == authority)
    #expect(
      try JSONDecoder().decode(CatalogAuthorityRecord.self, from: JSONEncoder().encode(authority))
        == authority)
  }

  /// Decodes a synthetic authority record whose members follow a fixed identifier and type.
  private static func authority(_ members: String) throws -> CatalogAuthorityRecord {
    let record = try CatalogRecord.decode(
      Data((#"{"record":{"naId":1,"recordType":"authority","# + members + "}}").utf8))
    return try #require(record.authorityRecord)
  }

  /// Decodes every line of one recorded fixture.
  private static func records(_ fixture: Fixture) throws -> [CatalogRecord] {
    try fixture.data().split(separator: 10).map { try CatalogRecord.decode(Data($0)) }
  }
}
