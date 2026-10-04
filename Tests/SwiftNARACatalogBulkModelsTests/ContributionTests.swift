import Foundation
import SwiftNARACatalogBulkModels
import SwiftNARACatalogBulkTestSupport
import Testing

@Suite(.timeLimit(.minutes(suiteTimeLimitMinutes)))
struct ContributionTests {
  @Test("Every fixture contribution projects its kind and a false machine-generation flag")
  func everyFixtureContributionProjectsItsKindAndAFalseMachineGenerationFlag() throws {
    let fixtures: [Fixture] = [
      .fdr, .geographicReference, .organization, .person, .rg11, .specificRecordsType,
      .topicalSubject,
    ]
    let records = try fixtures.flatMap(Self.records)
    let comments = records.flatMap { $0.comments ?? [] }
    let tags = records.flatMap { $0.tags ?? [] }
    let transcriptions = records.flatMap { $0.transcriptions ?? [] }
    #expect(comments.count == 3)
    #expect(tags.count == 135)
    #expect(transcriptions.count == 81)
    #expect(comments.allSatisfy { $0.contributionType == "comment" })
    #expect(tags.allSatisfy { $0.contributionType == "tag" })
    #expect(transcriptions.allSatisfy { $0.contributionType == "transcription" })
    let all = comments + tags + transcriptions
    #expect(all.allSatisfy { $0.isAIMachineGenerated == false })
    #expect(all.allSatisfy { $0.source["aiMachineGenerated"] == .bool(false) })
    #expect(all.allSatisfy { $0.recordType == "contribution" })
    #expect(all.allSatisfy { $0.target?.naID != nil })
    #expect(
      all.allSatisfy {
        $0.contributionSource == .communityMember || $0.contributionSource == .naraStaff
      })
  }

  @Test("A description comment projects its fixture attribution, target, and times")
  func aDescriptionCommentProjectsItsFixtureAttributionTargetAndTimes() throws {
    let record = try Self.records(.fdr)[1]
    #expect(record.naID == "122179401")
    let comments = try #require(record.comments)
    #expect(comments.count == 1)
    let comment = comments[0]
    #expect(
      comment.contribution
        == "Some of the corrections are hard to decipher. There are many shorthand comments.")
    #expect(comment.contributionID == "eb84a30d-add9-3baa-a60a-789d01e6430c")
    #expect(comment.contributionSequence == 1)
    #expect(comment.contributionSource == .communityMember)
    #expect(comment.contributionType == "comment")
    #expect(comment.createdAt == "2019-12-26 20:23:15")
    #expect(comment.updatedAt == "2019-12-26 20:23:15")
    #expect(comment.isAIMachineGenerated == false)
    #expect(comment.parentContributionID == nil)
    #expect(comment.contributors == nil)
    #expect(comment.contributor?["fullName"] == .string("Cindy Ellen Lachin"))
    #expect(comment.contributor?["naraStaff"] == .bool(false))
    #expect(comment.contributor?["userName"] == .string("Taleen"))
    let target = try #require(comment.target)
    #expect(target.naID == "122179401")
    #expect(target.objectID == "122179424")
    #expect(target.pageNumber == 22)
    #expect(record.tags?.count == 18)
    #expect(record.transcriptions?.count == 24)
  }

  @Test("Transcriptions keep source order and repeated sequence numbers")
  func transcriptionsKeepSourceOrderAndRepeatedSequenceNumbers() throws {
    let records = try Self.records(.rg11)
    #expect(records.map { $0.transcriptions?.count ?? 0 }.reduce(0, +) == 32)
    let record = records[1]
    #expect(record.naID == "299953")
    let transcriptions = try #require(record.transcriptions)
    #expect(transcriptions.count == 18)
    #expect(
      transcriptions.map(\.target?.objectID) == [
        "68123586", "68123594", "68123590", "68123597", "68123599", "68123588", "68123587",
        "68123589", "68123592", "68123600", "68123596", "68123598", "68123591", "68123601",
        "68123595", "68123593", "68123602", "68123585",
      ])
    #expect(
      transcriptions.map(\.contributionSequence) == [
        56, 2, 21, 12, 16, 20, 29, 17, 2, 16, 17, 20, 14, 13, 20, 2, 25, 18,
      ])
    #expect(
      transcriptions.map(\.target?.pageNumber) == [
        1, 9, 5, 12, 14, 3, 2, 4, 18, 15, 11, 13, 6, 16, 10, 8, 17, 18,
      ])
    #expect(transcriptions[0].contributionID == "319a4230-d55a-3e97-a98c-8f42c9222987")
    #expect(transcriptions[0].parentContributionID == "c1517dc8-638a-3c95-814f-9dc0f3c41b91")
    #expect(transcriptions[0].createdAt == "2017-09-28 14:16:31")
    #expect(transcriptions[17].contributionID == "c4a3d4e5-0431-3e1a-82cd-e1b53b8ef614")
    #expect(transcriptions.allSatisfy { $0.contributionSource == .communityMember })
    #expect(transcriptions.allSatisfy { $0.contributor == nil && $0.updatedAt == nil })
  }

  @Test("A transcription leaves the digital object's extracted text unchanged")
  func aTranscriptionLeavesTheDigitalObjectsExtractedTextUnchanged() throws {
    let record = try Self.records(.fdr)[1]
    let transcription = try #require(record.transcriptions?[23])
    #expect(transcription.target?.objectID == "122179424")
    #expect(transcription.target?.pageNumber == 22)
    #expect(transcription.contributionID == "5e2ddb06-b122-309c-ac87-45f5310affe5")
    #expect(transcription.contributionSequence == 16)
    #expect(transcription.contributors?.count == 16)
    let text = try #require(transcription.contribution)
    #expect(text.hasPrefix("CONFIDENTIAL\nSTATEMENTS FILE\nCONFIDENTIAL\nShorthand by Kannee\n"))

    let object = try #require(record.digitalObjects?[21])
    #expect(object.objectID == "122179424")
    let ocr = try #require(object.extractedText)
    #expect(ocr.hasPrefix("\nCONFIDEL TATEMENTS FILE\n-\nCONFIDE\nN\nShorth a nd By Kannee\n"))
    #expect(object.source["completeExtractedText"] == nil)
    #expect(ocr != text)
  }

  @Test("Staff transcriptions keep every contributor entry and the parent identifier")
  func staffTranscriptionsKeepEveryContributorEntryAndTheParentIdentifier() throws {
    let record = try Self.records(.rg11)[10]
    #expect(record.naID == "100358199")
    let transcription = try #require(record.transcriptions?.first)
    #expect(record.transcriptions?.count == 6)
    #expect(transcription.contributionSource == .naraStaff)
    #expect(transcription.contributionID == "27f82e71-f06f-34ba-bd54-d2921c19297a")
    #expect(transcription.parentContributionID == "52a98fe7-52bc-39c1-8757-7dd7d19a4211")
    #expect(transcription.contributionSequence == 2)
    #expect(transcription.createdAt == "2021-02-12 14:39:55")
    #expect(transcription.contributor == nil)
    let contributors = try #require(transcription.contributors)
    #expect(contributors.count == 2)
    #expect(contributors[0]["contributionSequence"] == .integer(1))
    #expect(contributors[0]["createdAt"] == .string("2021-02-12 14:39:01"))
    #expect(contributors[1]["contributionSequence"] == .integer(2))
    #expect(contributors[1]["createdAt"] == .string("2021-02-12 14:39:55"))
    #expect(contributors.allSatisfy { $0["fullName"] == .string("Rebecca Crawford") })
    #expect(contributors.allSatisfy { $0["naraStaff"] == .bool(true) })
    #expect(transcription.target?.objectID == "114274029")
    #expect(transcription.target?.pageNumber == 1)
  }

  @Test("Authority tags target the authority without an object or page")
  func authorityTagsTargetTheAuthorityWithoutAnObjectOrPage() throws {
    let record = try Self.records(.topicalSubject)[0]
    #expect(record.authorityRecord?.naID == "10636684")
    let tags = try #require(record.tags)
    #expect(tags.count == 1)
    let tag = tags[0]
    #expect(tag.contribution == "wikidata=q5419945")
    #expect(tag.contributionID == "a4fb1f5d-f436-342b-b2b7-26009fcc1784")
    #expect(tag.contributionSource == .naraStaff)
    #expect(tag.contributionSequence == nil)
    #expect(tag.createdAt == "2019-05-22 22:14:02")
    #expect(tag.contributor?["userName"] == .string("dominic"))
    #expect(tag.target?.naID == "10636684")
    #expect(tag.target?.objectID == nil)
    #expect(tag.target?.pageNumber == nil)
    #expect(tag.target?.source == .object(["naId": .integer(10_636_684)]))
    #expect(record.comments == nil)
    #expect(record.transcriptions == nil)

    let organization = try Self.records(.organization)[55]
    #expect(organization.naID == "10545282")
    let organizationTags = try #require(organization.tags)
    #expect(organizationTags.count == 2)
    #expect(organizationTags[0].target?.objectID == nil)
    let objectTag = organizationTags[1]
    #expect(objectTag.contribution == "wikidata=q458620")
    #expect(objectTag.target?.objectID == "10474384")
    #expect(objectTag.target?.pageNumber == nil)
  }

  @Test("Authority comments with the same sequence number stay separate and ordered")
  func authorityCommentsWithTheSameSequenceNumberStaySeparateAndOrdered() throws {
    let record = try Self.records(.topicalSubject)[4]
    #expect(record.naID == "10639229")
    let comments = try #require(record.comments)
    #expect(
      comments.map(\.contributionID) == [
        "c03b102f-b2ef-3a15-9529-6ea1309fabf2", "68902178-4870-3f5f-a451-c2b1c3377751",
      ])
    #expect(comments.map(\.contributionSequence) == [1, 1])
    #expect(comments.map(\.createdAt) == ["2017-02-10 10:09:37", "2017-02-10 10:11:59"])
    #expect(comments.allSatisfy { $0.target?.naID == "10639229" && $0.target?.objectID == nil })
    #expect(record.tags?.count == 1)
  }

  @Test("Contribution metadata arrays stay separate and are never joined to contributions")
  func contributionMetadataArraysStaySeparateAndAreNeverJoinedToContributions() throws {
    let rg11 = try Self.records(.rg11)[1]
    let metadata = rg11.contributionMetadata
    #expect(metadata.comments == nil)
    #expect(metadata.tags?.count == 25)
    #expect(metadata.transcriptions?.count == 18)
    let first = try #require(metadata.transcriptions?.first)
    #expect(first["uuid"] == .string("7f1c609e-9a2d-4086-b2a2-735e5dd3c896"))
    #expect(first["ingestTime"] == .string("2026-03-01 13:41:30.568502"))
    #expect(first["fileName"] == .string("None"))
    #expect(
      first["controlGroup"]
        == .object([
          "indexName": .string("contributions-transcriptions"), "naId": .integer(299_953),
          "type": .string("transcriptions"),
        ]))
    #expect(metadata.tags?.first?["uuid"] == .string("796639e3-8b77-45c6-98b9-58bf81c01d75"))
    #expect(rg11.transcriptions?.first?.source["uuid"] == nil)

    let fdr = try Self.records(.fdr)[1]
    #expect(fdr.contributionMetadata.comments?.count == 1)
    #expect(
      fdr.contributionMetadata.comments?.first?["uuid"]
        == .string("47f28684-2380-490e-b6c2-ee670c2553a2"))
    #expect(fdr.contributionMetadata.source == fdr.source)
  }

  @Test("Records without contributions project no contribution arrays")
  func recordsWithoutContributionsProjectNoContributionArrays() throws {
    let records = try Self.records(.specificRecordsType) + [Self.records(.rg11)[0]]
    #expect(records.count == 3)
    for record in records {
      #expect(record.comments == nil)
      #expect(record.tags == nil)
      #expect(record.transcriptions == nil)
      #expect(record.contributionMetadata.comments == nil)
      #expect(record.contributionMetadata.tags == nil)
      #expect(record.contributionMetadata.transcriptions == nil)
    }
  }

  @Test("Synthetic unknown kinds and categories are retained exactly")
  func syntheticUnknownKindsAndCategoriesAreRetainedExactly() throws {
    // Synthetic: an unknown contribution type and category, and an unknown top-level array.
    let record = try Self.record(
      #""record_tag":[{"contributionType":"annotation","source":"volunteerGroup","#
        + #""recordType":"delete","aiMachineGenerated":true}],"#
        + #""record_annotation":[{"contribution":"x"}],"metadata_annotation":[{"uuid":"y"}]"#)
    let tag = try #require(record.tags?.first)
    #expect(tag.contributionType == "annotation")
    #expect(tag.contributionSource == CatalogContributionSource(rawValue: "volunteerGroup"))
    #expect(tag.contributionSource != .communityMember && tag.contributionSource != .naraStaff)
    #expect(tag.recordType == "delete")
    #expect(tag.isAIMachineGenerated == true)
    #expect(record.source["record_annotation"]?.array?.count == 1)
    #expect(record.source["metadata_annotation"]?.array?.count == 1)
    #expect(record.comments == nil && record.transcriptions == nil)
    #expect(record.contributionMetadata.tags == nil)
  }

  @Test("Synthetic null and wrong-shaped flags project nil while the source keeps them")
  func syntheticNullAndWrongShapedFlagsProjectNilWhileTheSourceKeepsThem() throws {
    // Synthetic: null, string, integer, and absent machine-generation flags.
    let record = try Self.record(
      #""record_comment":[{"aiMachineGenerated":null},{"aiMachineGenerated":"true"},"#
        + #"{"aiMachineGenerated":1},{}]"#)
    let comments = try #require(record.comments)
    #expect(comments.map(\.isAIMachineGenerated) == [nil, nil, nil, nil])
    #expect(comments[0].source["aiMachineGenerated"] == .null)
    #expect(comments[1].source["aiMachineGenerated"] == .string("true"))
    #expect(comments[2].source["aiMachineGenerated"] == .integer(1))
    #expect(comments[3].source["aiMachineGenerated"] == nil)
  }

  @Test("Synthetic missing and wrong-shaped targets project nil while the source keeps them")
  func syntheticMissingAndWrongShapedTargetsProjectNilWhileTheSourceKeepsThem() throws {
    // Synthetic: absent, null, string, and malformed targets.
    let record = try Self.record(
      #""record_transcription":[{},{"target":null},{"target":"122179401"},"#
        + #"{"target":{"naId":"00012","objectId":7,"pageNum":"3"}},"#
        + #"{"target":{"naId":18446744073709551615,"pageNum":2.5}}]"#)
    let transcriptions = try #require(record.transcriptions)
    #expect(transcriptions.count == 5)
    #expect(transcriptions[0].target == nil && transcriptions[0].source["target"] == nil)
    #expect(transcriptions[1].target == nil && transcriptions[1].source["target"] == .null)
    #expect(transcriptions[2].target == nil)
    #expect(transcriptions[2].source["target"] == .string("122179401"))
    let malformed = try #require(transcriptions[3].target)
    #expect(malformed.naID == "00012")
    #expect(malformed.objectID == "7")
    #expect(malformed.pageNumber == nil)
    #expect(malformed.source["pageNum"] == .string("3"))
    let large = try #require(transcriptions[4].target)
    #expect(large.naID == "18446744073709551615")
    #expect(large.pageNumber == nil)
  }

  @Test("Synthetic contributors without names and conflicting attribution are retained as supplied")
  func syntheticContributorsWithoutNamesAndConflictingAttributionAreRetainedAsSupplied() throws {
    // Synthetic: a community category with a staff contributor, and contributors without names.
    let record = try Self.record(
      #""record_tag":[{"source":"communityMember","contributor":{"naraStaff":true,"userId":"u1"}}],"#
        + #""record_transcription":[{"contributors":[{"userId":"u2"},null,"u3"],"#
        + #""contributor":{"userId":"u4"}}]"#)
    let tag = try #require(record.tags?.first)
    #expect(tag.contributionSource == .communityMember)
    #expect(tag.contributor == .object(["naraStaff": .bool(true), "userId": .string("u1")]))
    #expect(tag.contributor?["fullName"] == nil)
    let transcription = try #require(record.transcriptions?.first)
    #expect(
      transcription.contributors == [.object(["userId": .string("u2")]), .null, .string("u3")])
    #expect(transcription.contributor == .object(["userId": .string("u4")]))
    #expect(transcription.contributionSource == nil)
  }

  @Test("Synthetic malformed contribution arrays and members do not erase the record")
  func syntheticMalformedContributionArraysAndMembersDoNotEraseTheRecord() throws {
    // Synthetic: non-object elements, wrong-shaped arrays, and wrong-shaped members.
    let record = try Self.record(
      #""record_tag":[1,null,{"contribution":"a","contributionSequence":"2"},"#
        + #"{"contribution":7,"contributionSequence":2.5,"contributionId":12,"createdAt":5}],"#
        + #""record_comment":{"contribution":"x"},"record_transcription":null,"#
        + #""metadata_tag":"none","metadata_comment":[],"metadata_transcription":[null]"#)
    #expect(record.naID == "1")
    #expect(record.archivalDescription?.naID == "1")
    let tags = try #require(record.tags)
    #expect(tags.count == 4)
    #expect(tags[0].source == .integer(1) && tags[0].contribution == nil && tags[0].target == nil)
    #expect(tags[1].source == .null && tags[1].contributionID == nil)
    #expect(tags[2].contribution == "a" && tags[2].contributionSequence == nil)
    #expect(tags[3].contribution == nil && tags[3].contributionSequence == nil)
    #expect(tags[3].contributionID == "12" && tags[3].createdAt == nil)
    #expect(record.comments == nil)
    #expect(record.source["record_comment"]?.object != nil)
    #expect(record.transcriptions == nil)
    #expect(record.source["record_transcription"] == .null)
    #expect(record.contributionMetadata.tags == nil)
    #expect(record.contributionMetadata.comments == [])
    #expect(record.contributionMetadata.transcriptions == [.null])
  }

  @Test("A contribution round-trips through its Codable form with its source unchanged")
  func aContributionRoundTripsThroughItsCodableFormWithItsSourceUnchanged() throws {
    let contribution = try #require(Self.records(.fdr)[1].comments?.first)
    let decoded = try JSONDecoder().decode(
      CatalogContribution.self, from: JSONEncoder().encode(contribution))
    #expect(decoded == contribution)
    #expect(decoded.source["target"]?["pageNum"] == .integer(22))
  }

  /// Decodes a synthetic description envelope with the given top-level members.
  private static func record(_ members: String) throws -> CatalogRecord {
    try CatalogRecord.decode(
      Data((#"{"record":{"naId":1,"recordType":"description"},"# + members + "}").utf8))
  }

  /// Decodes every line of one recorded fixture.
  private static func records(_ fixture: Fixture) throws -> [CatalogRecord] {
    try fixture.data().split(separator: 10).map { try CatalogRecord.decode(Data($0)) }
  }
}
