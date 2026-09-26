import Foundation
import SwiftNARACatalogBulkModels
import SwiftNARACatalogBulkTestSupport
import Testing

@Suite(.timeLimit(.minutes(suiteTimeLimitMinutes)))
struct DirectoryTests {
  static let bucket = "nara-national-archives-catalog"
  static let collectionsFirstPrefixes = [
    "descriptions/collections/coll_1AV/", "descriptions/collections/coll_AAS/",
    "descriptions/collections/coll_AASA/",
  ]
  static let collectionsFirstToken =
    "1vKoy990xdAaYk7IeulTw7YN3lqzxgzJUobs6jaPU768AB6/vlB7TQLVrLOZ6Lxs44+gY0H59tiSXR7041G3+0Zw754okniFAsEavEOa0D2I="
  static let collectionsSecondToken =
    "1bjNCKdEexoAtW5wz12Lrll5qy8q92/HGB/ExFLhOJFqZS16k+WXQKYW9NKIkG98L9kHdUO+kfTGHCVAcW1cEXsOWso29XGtWqaGoaLz8FtY="

  @Test("Each directory maps to its exact storage prefix")
  func eachDirectoryMapsToItsExactStoragePrefix() {
    #expect(BulkDirectory.allCases == [.authorityRecords, .collections, .recordGroups])
    #expect(BulkDirectory.authorityRecords.prefix == "authority-records/")
    #expect(BulkDirectory.collections.prefix == "descriptions/collections/")
    #expect(BulkDirectory.recordGroups.prefix == "descriptions/record-groups/")
  }

  @Test("Query construction validates the bound and token")
  func queryConstructionValidatesTheBoundAndToken() throws {
    let query = try BulkDirectoryQuery(directory: .collections)
    #expect(query.continuationToken == nil)
    #expect(query.directory == .collections)
    #expect(query.maxKeys == 1000)
    #expect(try BulkDirectoryQuery(directory: .recordGroups, maxKeys: 1).maxKeys == 1)
    for maxKeys in [0, 1001] {
      #expect(throws: ManifestError.invalidQuery) {
        try BulkDirectoryQuery(directory: .collections, maxKeys: maxKeys)
      }
    }
    for token in ["", "a\u{0}b", "a\u{7F}"] {
      #expect(throws: ManifestError.invalidQuery) {
        try BulkDirectoryQuery(continuationToken: token, directory: .collections)
      }
    }
  }

  @Test("Captured collection pages continue with the exact echoed token")
  func capturedCollectionPagesContinueWithTheExactEchoedToken() throws {
    let first = Self.collectionsPage()
    let second = Self.collectionsPage(
      continuationToken: Self.collectionsFirstToken,
      nextContinuationToken: Self.collectionsSecondToken,
      prefixes: [
        "descriptions/collections/coll_AAW/", "descriptions/collections/coll_ABC/",
        "descriptions/collections/coll_ABDIL/",
      ])
    try Self.expectCaptured(first, in: .directoryCollectionsFirst)
    try Self.expectCaptured(second, in: .directoryCollectionsSecond)
    #expect(first.objects.isEmpty)
    let query = try BulkDirectoryQuery(directory: .collections, maxKeys: 3)
    let next = try #require(try query.next(after: first))
    #expect(next.continuationToken == Self.collectionsFirstToken)
    #expect(next.directory == .collections)
    #expect(next.maxKeys == 3)
    #expect(try next.next(after: second)?.continuationToken == Self.collectionsSecondToken)
  }

  @Test("Captured record group prefixes stay lexical and unrewritten")
  func capturedRecordGroupPrefixesStayLexicalAndUnrewritten() throws {
    let prefixes = [
      "descriptions/record-groups/rg_1/", "descriptions/record-groups/rg_10/",
      "descriptions/record-groups/rg_100/",
    ]
    let page = Self.collectionsPage(
      nextContinuationToken:
        "1Bosm1TzvfhXnQ/bUBDteAJnLrhWquwvcQB4LCb68zQL6kf41OplPJMIQT/sSYUvjX6tve8edu0tBtCXgM9ZWxpaW9NOj6VpsSJWwOA9SLmQ=",
      prefix: "descriptions/record-groups/", prefixes: prefixes)
    try Self.expectCaptured(page, in: .directoryRecordGroups)
    let query = try BulkDirectoryQuery(directory: .recordGroups, maxKeys: 3)
    #expect(try query.next(after: page)?.continuationToken == page.nextContinuationToken)
    let partitions = try page.prefixes.map { prefix throws(ManifestError) in
      try BulkPartitionReference(directory: .recordGroups, prefix: prefix)
    }
    #expect(partitions.map(\.prefix) == prefixes)
    #expect(partitions.allSatisfy { $0.directory == .recordGroups })
    // Synthetic: a zero-padded code is kept exactly as listed.
    let padded = try BulkPartitionReference(
      directory: .recordGroups, prefix: "descriptions/record-groups/rg_020/")
    #expect(padded.prefix == "descriptions/record-groups/rg_020/")
    #expect(try ManifestQuery(prefix: padded.prefix).prefix == "descriptions/record-groups/rg_020/")
  }

  @Test("The terminal authority page carries its marker object beside five prefixes")
  func theTerminalAuthorityPageCarriesItsMarkerObjectBesideFivePrefixes() throws {
    let prefixes = [
      "authority-records/geographic-reference/", "authority-records/organization/",
      "authority-records/person/", "authority-records/specific-records-type/",
      "authority-records/topical-subject/",
    ]
    let page = BulkDirectoryPage(
      delimiter: "/", isTruncated: false, keyCount: 6, maxKeys: 20, name: Self.bucket,
      objects: [Self.object("authority-records/")], prefix: "authority-records/",
      prefixes: prefixes)
    try Self.expectCaptured(page, in: .directoryAuthorityRecords)
    let query = try BulkDirectoryQuery(directory: .authorityRecords, maxKeys: 20)
    #expect(try query.next(after: page) == nil)
    let partitions = try prefixes.map { prefix throws(ManifestError) in
      try BulkPartitionReference(directory: .authorityRecords, prefix: prefix)
    }
    #expect(partitions.map(\.prefix) == prefixes)
    #expect(throws: ManifestError.invalidQuery) {
      try BulkPartitionReference(directory: .authorityRecords, prefix: "authority-records/")
    }
  }

  @Test("An undelimited listing is not a directory page")
  func anUndelimitedListingIsNotADirectoryPage() throws {
    let keys =
      ["authority-records/"]
      + ["1", "10", "100", "101", "102", "103", "104"].map {
        "authority-records/geographic-reference/geographic-reference-\($0).jsonl"
      }
    let page = BulkDirectoryPage(
      isTruncated: true, keyCount: 8, maxKeys: 8, name: Self.bucket,
      nextContinuationToken:
        "1XCTiLI3clAQ+DUILqzTDKDfIEFMj4An6LPcIBAE9XlbxiGAN1sJ9ndMmecblO12BiofQP4STVgA1pfOgDkcg0p1Fk163O2xG6YLRXkj8N/ykhXSy4ZMVn3x2tsQc6Wf2VKNSy5y164gB6GIbTUdH+w==",
      objects: keys.map(Self.object), prefix: "authority-records/", prefixes: [])
    try Self.expectCaptured(page, in: .directoryAuthorityRecordsUndelimited)
    #expect(throws: ManifestError.inconsistentPage) {
      try BulkDirectoryQuery(directory: .authorityRecords, maxKeys: 8).next(after: page)
    }
  }

  @Test("Echo mismatches fail as inconsistent pages")
  func echoMismatchesFailAsInconsistentPages() throws {
    let query = try BulkDirectoryQuery(directory: .collections, maxKeys: 3)
    // Synthetic: each page differs from the captured first collections page in one field.
    let mismatches = [
      Self.collectionsPage(name: "another-bucket"),
      Self.collectionsPage(prefix: "descriptions/record-groups/"),
      Self.collectionsPage(delimiter: nil),
      Self.collectionsPage(delimiter: ","),
      Self.collectionsPage(maxKeys: 4),
      Self.collectionsPage(continuationToken: "unrequested"),
      Self.collectionsPage(keyCount: 2),
      Self.collectionsPage(
        keyCount: 4, prefixes: Self.collectionsFirstPrefixes + ["descriptions/collections/x/"]),
      Self.collectionsPage(isTruncated: false),
    ]
    for page in mismatches {
      #expect(throws: ManifestError.inconsistentPage) { try query.next(after: page) }
    }
  }

  @Test("Truncated pages require a new token and at least one entry")
  func truncatedPagesRequireANewTokenAndAtLeastOneEntry() throws {
    let query = try BulkDirectoryQuery(directory: .collections, maxKeys: 3)
    // Synthetic: truncated pages without usable continuation.
    for page in [
      Self.collectionsPage(nextContinuationToken: nil),
      Self.collectionsPage(nextContinuationToken: ""),
      Self.collectionsPage(keyCount: 0, prefixes: []),
    ] {
      #expect(throws: ManifestError.missingContinuation) { try query.next(after: page) }
    }
    // Synthetic: the next token repeats the requested token.
    let repeated = Self.collectionsPage(continuationToken: "same", nextContinuationToken: "same")
    #expect(throws: ManifestError.repeatedContinuation) {
      try BulkDirectoryQuery(continuationToken: "same", directory: .collections, maxKeys: 3)
        .next(after: repeated)
    }
  }

  @Test("Out-of-scope and nested entries are rejected")
  func outOfScopeAndNestedEntriesAreRejected() throws {
    let query = try BulkDirectoryQuery(directory: .collections, maxKeys: 3)
    // Synthetic: prefixes that do not name one immediate child of the collections directory.
    for prefix in [
      "descriptions/record-groups/rg_1/", "descriptions/collections/",
      "descriptions/collections//", "descriptions/collections/coll_A/nested/",
      "descriptions/collections/coll_A", "descriptions/collections/./",
      "descriptions/collections/../", "descriptions/collections/coll\\A/",
      "descriptions/collections/coll\u{0}A/", "Descriptions/collections/coll_A/",
    ] {
      #expect(throws: ManifestError.invalidQuery, "\(prefix)") {
        try BulkPartitionReference(directory: .collections, prefix: prefix)
      }
      let page = Self.collectionsPage(
        isTruncated: false, keyCount: 1, nextContinuationToken: nil, prefixes: [prefix])
      #expect(throws: ManifestError.inconsistentPage, "\(prefix)") { try query.next(after: page) }
    }
    // Synthetic: objects nested below a child or outside the directory.
    for key in [
      "descriptions/collections/coll_A/coll_A-1.jsonl", "descriptions/record-groups/rg_1.jsonl",
    ] {
      let page = Self.collectionsPage(
        isTruncated: false, keyCount: 1, nextContinuationToken: nil, objects: [Self.object(key)],
        prefixes: [])
      #expect(throws: ManifestError.inconsistentPage, "\(key)") { try query.next(after: page) }
    }
  }

  @Test("Duplicate prefixes on a page are accepted as listed")
  func duplicatePrefixesOnAPageAreAcceptedAsListed() throws {
    // Synthetic: S3 does not promise uniqueness across or within pages; nothing is deduplicated.
    let duplicate = "descriptions/collections/coll_1AV/"
    let page = Self.collectionsPage(
      isTruncated: false, keyCount: 2, nextContinuationToken: nil,
      prefixes: [duplicate, duplicate])
    #expect(try BulkDirectoryQuery(directory: .collections, maxKeys: 3).next(after: page) == nil)
    #expect(page.prefixes == [duplicate, duplicate])
  }

  @Test("Every captured delimited listing decodes with its literal entries")
  func everyCapturedDelimitedListingDecodesWithItsLiteralEntries() throws {
    let first = try BulkDirectoryPage.decode(Fixture.directoryCollectionsFirst.data())
    #expect(first == Self.collectionsPage())
    #expect(first.prefixes.count == 3)
    #expect(first.objects.isEmpty)
    let second = try BulkDirectoryCodec.decode(Fixture.directoryCollectionsSecond.data())
    #expect(
      second
        == Self.collectionsPage(
          continuationToken: Self.collectionsFirstToken,
          nextContinuationToken: Self.collectionsSecondToken,
          prefixes: [
            "descriptions/collections/coll_AAW/", "descriptions/collections/coll_ABC/",
            "descriptions/collections/coll_ABDIL/",
          ]))
    let recordGroups = try BulkDirectoryPage.decode(Fixture.directoryRecordGroups.data())
    #expect(
      recordGroups
        == Self.collectionsPage(
          nextContinuationToken:
            "1Bosm1TzvfhXnQ/bUBDteAJnLrhWquwvcQB4LCb68zQL6kf41OplPJMIQT/sSYUvjX6tve8edu0tBtCXgM9ZWxpaW9NOj6VpsSJWwOA9SLmQ=",
          prefix: "descriptions/record-groups/",
          prefixes: [
            "descriptions/record-groups/rg_1/", "descriptions/record-groups/rg_10/",
            "descriptions/record-groups/rg_100/",
          ]))
    let authority = try BulkDirectoryPage.decode(Fixture.directoryAuthorityRecords.data())
    #expect(
      authority
        == BulkDirectoryPage(
          delimiter: "/", isTruncated: false, keyCount: 6, maxKeys: 20, name: Self.bucket,
          objects: [Self.object("authority-records/")], prefix: "authority-records/",
          prefixes: [
            "authority-records/geographic-reference/", "authority-records/organization/",
            "authority-records/person/", "authority-records/specific-records-type/",
            "authority-records/topical-subject/",
          ]))
    #expect(authority.prefixes.count == 5)
    #expect(authority.objects.count == 1)
    #expect(
      try BulkDirectoryQuery(directory: .authorityRecords, maxKeys: 20).next(after: authority)
        == nil)
  }

  @Test("An undelimited listing decodes but does not continue as a directory")
  func anUndelimitedListingDecodesButDoesNotContinueAsADirectory() throws {
    let page = try BulkDirectoryPage.decode(Fixture.directoryAuthorityRecordsUndelimited.data())
    #expect(page.delimiter == nil)
    #expect(page.prefixes.isEmpty)
    #expect(page.isTruncated)
    #expect(page.keyCount == 8)
    #expect(page.maxKeys == 8)
    #expect(page.name == Self.bucket)
    #expect(page.prefix == "authority-records/")
    #expect(page.continuationToken == nil)
    #expect(
      page.nextContinuationToken
        == "1XCTiLI3clAQ+DUILqzTDKDfIEFMj4An6LPcIBAE9XlbxiGAN1sJ9ndMmecblO12BiofQP4STVgA1pfOgDkcg0p1Fk163O2xG6YLRXkj8N/ykhXSy4ZMVn3x2tsQc6Wf2VKNSy5y164gB6GIbTUdH+w=="
    )
    #expect(
      page.objects.map(\.key) == [
        "authority-records/",
        "authority-records/geographic-reference/geographic-reference-1.jsonl",
        "authority-records/geographic-reference/geographic-reference-10.jsonl",
        "authority-records/geographic-reference/geographic-reference-100.jsonl",
        "authority-records/geographic-reference/geographic-reference-101.jsonl",
        "authority-records/geographic-reference/geographic-reference-102.jsonl",
        "authority-records/geographic-reference/geographic-reference-103.jsonl",
        "authority-records/geographic-reference/geographic-reference-104.jsonl",
      ])
    #expect(page.objects[0] == Self.object("authority-records/"))
    #expect(
      page.objects[1]
        == BulkObject(
          eTag: "\"97464265bf78cc7104985756a1b34e10\"",
          key: "authority-records/geographic-reference/geographic-reference-1.jsonl",
          lastModified: "2026-04-06T17:54:57.000Z", size: 31042, storageClass: "STANDARD"))
    #expect(throws: ManifestError.inconsistentPage) {
      try BulkDirectoryQuery(directory: .authorityRecords, maxKeys: 8).next(after: page)
    }
  }

  @Test("Malformed directory listings cannot become a successful page")
  func malformedDirectoryListingsCannotBecomeASuccessfulPage() throws {
    let data = try Fixture.directoryAuthorityRecords.data()
    let xml = String(decoding: data, as: UTF8.self)
    let person = "<Prefix>authority-records/person/</Prefix>"
    // Synthetic: each input changes the captured terminal authority listing in one place.
    let malformed = [
      xml.replacingOccurrences(of: "<Delimiter>/</Delimiter>", with: "<Delimiter>,</Delimiter>"),
      xml.replacingOccurrences(
        of: "<Delimiter>/</Delimiter>", with: "<Delimiter>/</Delimiter><Delimiter>/</Delimiter>"),
      xml.replacingOccurrences(of: "<Delimiter>/</Delimiter>", with: ""),
      xml.replacingOccurrences(of: "<KeyCount>6</KeyCount>", with: "<KeyCount>5</KeyCount>"),
      xml.replacingOccurrences(of: "<KeyCount>6</KeyCount>", with: "<KeyCount>7</KeyCount>"),
      xml.replacingOccurrences(of: "<MaxKeys>20</MaxKeys>", with: "<MaxKeys>5</MaxKeys>"),
      xml.replacingOccurrences(
        of: "<IsTruncated>false</IsTruncated>", with: "<IsTruncated>maybe</IsTruncated>"),
      xml.replacingOccurrences(of: person, with: person + "<Prefix>authority-records/x/</Prefix>"),
      xml.replacingOccurrences(of: person, with: person + "<Extra/>"),
      xml.replacingOccurrences(of: person, with: ""),
      xml.replacingOccurrences(
        of: "<CommonPrefixes>" + person, with: "<CommonPrefixes xmlns=\"urn:other\">" + person),
      xml.replacingOccurrences(of: "ListBucketResult", with: "ListAllMyBucketsResult"),
      xml + "<extra/>",
      "<!DOCTYPE ListBucketResult [<!ENTITY external SYSTEM 'file:///etc/passwd'>]>" + xml,
    ]
    for input in malformed {
      #expect(throws: CatalogDecodingError.malformedXML) {
        try BulkDirectoryCodec.decode(Data(input.utf8))
      }
    }
    #expect(throws: CatalogDecodingError.limitExceeded) {
      try BulkDirectoryCodec.decode(data, maximumBytes: data.count - 1)
    }
    #expect(throws: CatalogDecodingError.limitExceeded) {
      try BulkDirectoryCodec.decode(
        Data((String(repeating: "<x>", count: 17) + String(repeating: "</x>", count: 17)).utf8))
    }
  }

  @Test("Namespaced and URL-encoded prefixes decode portably")
  func namespacedAndURLEncodedPrefixesDecodePortably() throws {
    // Synthetic: a namespaced, URL-encoded listing interleaving objects and prefixes.
    let xml = """
      <?xml version="1.0" encoding="UTF-8"?>
      <s:ListBucketResult xmlns:s="http://s3.amazonaws.com/doc/2006-03-01/">
      <s:Name>nara-national-archives-catalog</s:Name>
      <s:Prefix>descriptions%2Fcollections%2F</s:Prefix><s:EncodingType>url</s:EncodingType>
      <s:Delimiter>%2F</s:Delimiter><s:MaxKeys>3</s:MaxKeys><s:KeyCount>3</s:KeyCount>
      <s:IsTruncated>false</s:IsTruncated>
      <s:CommonPrefixes><s:Prefix>descriptions/collections/coll%20A%26B/</s:Prefix></s:CommonPrefixes>
      <s:Contents><s:Key>descriptions/collections/</s:Key><s:Size>0</s:Size>
      <s:LastModified>2021-02-27T02:56:26.000Z</s:LastModified><s:ETag>&quot;opaque&quot;</s:ETag></s:Contents>
      <s:CommonPrefixes><s:Prefix><![CDATA[descriptions/collections/coll_1AV/]]></s:Prefix></s:CommonPrefixes>
      </s:ListBucketResult>
      """
    let page = try BulkDirectoryCodec.decode(Data(xml.utf8))
    #expect(page.delimiter == "/")
    #expect(page.prefix == "descriptions/collections/")
    #expect(
      page.prefixes == [
        "descriptions/collections/coll A&B/", "descriptions/collections/coll_1AV/",
      ])
    #expect(page.objects.map(\.key) == ["descriptions/collections/"])
    #expect(page.objects[0].storageClass == nil)
  }

  @Test("Directory endpoints reproduce the captured listing URLs")
  func directoryEndpointsReproduceTheCapturedListingURLs() throws {
    let origin = "https://nara-national-archives-catalog.s3.amazonaws.com"
    let cases: [(BulkDirectoryQuery, String)] = [
      (
        try BulkDirectoryQuery(directory: .collections, maxKeys: 3),
        "/?delimiter=%2F&list-type=2&max-keys=3&prefix=descriptions%2Fcollections%2F"
      ),
      (
        try BulkDirectoryQuery(
          continuationToken: Self.collectionsFirstToken, directory: .collections, maxKeys: 3),
        "/?continuation-token=1vKoy990xdAaYk7IeulTw7YN3lqzxgzJUobs6jaPU768AB6%2FvlB7TQLVrLOZ6Lxs44"
          + "%2BgY0H59tiSXR7041G3%2B0Zw754okniFAsEavEOa0D2I%3D&delimiter=%2F&list-type=2&max-keys=3"
          + "&prefix=descriptions%2Fcollections%2F"
      ),
      (
        try BulkDirectoryQuery(directory: .recordGroups, maxKeys: 3),
        "/?delimiter=%2F&list-type=2&max-keys=3&prefix=descriptions%2Frecord-groups%2F"
      ),
      (
        try BulkDirectoryQuery(directory: .authorityRecords, maxKeys: 20),
        "/?delimiter=%2F&list-type=2&max-keys=20&prefix=authority-records%2F"
      ),
    ]
    for (query, path) in cases {
      let endpoint = Endpoint.directory(query)
      #expect(endpoint.path == path)
      #expect(endpoint.url.absoluteString == origin + path)
      #expect(endpoint.directoryQuery == query)
      #expect(endpoint.manifestQuery == nil)
      let linked = try #require(Endpoint<BulkDirectoryPage>(link: endpoint.url))
      #expect(linked.path == path)
      #expect(linked.directoryQuery == nil)
    }
    let manifest = Endpoint.manifest(try ManifestQuery(maxKeys: 8, prefix: "authority-records/"))
    #expect(manifest.path == "/?list-type=2&max-keys=8&prefix=authority-records%2F")
    #expect(manifest.directoryQuery == nil)
  }

  @Test("Directory requests are inspectable values in every call form")
  func directoryRequestsAreInspectableValuesInEveryCallForm() throws {
    let query = try BulkDirectoryQuery(directory: .recordGroups, maxKeys: 3)
    let stored = CatalogBulkRequest.directory(query)
    let annotated: CatalogBulkRequest<BulkDirectoryPage> = stored
    let contextual: CatalogBulkRequest<BulkDirectoryPage> = .directory(query)
    let named = try CatalogBulkRequest.threeRecordGroups()
    #expect(stored.resolution == .directory(query))
    #expect(annotated == contextual && contextual == named)
    #expect(Self.responseType(of: stored) == BulkDirectoryPage.self)
    let endpoint: Endpoint<BulkDirectoryPage> = .directory(query)
    let single = CatalogBulkRequest(endpoint: endpoint)
    #expect(single.resolution == .endpoint(endpoint))
    #expect(single != stored)
    let other = CatalogBulkRequest.directory(try BulkDirectoryQuery(directory: .collections))
    #expect(other.resolution == .directory(try BulkDirectoryQuery(directory: .collections)))
    #expect(other != stored)
  }

  /// The response type a request was inferred with, read from its generic parameter.
  static func responseType<Response>(of _: CatalogBulkRequest<Response>) -> Response.Type {
    Response.self
  }

  /// A page shaped like the captured first collections page, with fields overridable.
  static func collectionsPage(
    continuationToken: String? = nil, delimiter: String? = "/", isTruncated: Bool = true,
    keyCount: Int = 3, maxKeys: Int = 3, name: String = bucket,
    nextContinuationToken: String? = collectionsFirstToken, objects: [BulkObject] = [],
    prefix: String = "descriptions/collections/", prefixes: [String] = collectionsFirstPrefixes
  ) -> BulkDirectoryPage {
    BulkDirectoryPage(
      continuationToken: continuationToken, delimiter: delimiter, isTruncated: isTruncated,
      keyCount: keyCount, maxKeys: maxKeys, name: name,
      nextContinuationToken: nextContinuationToken, objects: objects, prefix: prefix,
      prefixes: prefixes)
  }

  /// Confirms a hand-built page states only what the recorded XML states.
  static func expectCaptured(_ page: BulkDirectoryPage, in fixture: Fixture) throws {
    let xml = String(decoding: try fixture.data(), as: UTF8.self)
    var elements = [
      "<Name>\(page.name)</Name>", "<Prefix>\(page.prefix)</Prefix>",
      "<KeyCount>\(page.keyCount)</KeyCount>", "<MaxKeys>\(page.maxKeys)</MaxKeys>",
      "<IsTruncated>\(page.isTruncated)</IsTruncated>",
    ]
    elements += page.prefixes.map { "<CommonPrefixes><Prefix>\($0)</Prefix></CommonPrefixes>" }
    elements += page.objects.map { "<Contents><Key>\($0.key)</Key>" }
    if let delimiter = page.delimiter { elements.append("<Delimiter>\(delimiter)</Delimiter>") }
    if let token = page.continuationToken {
      elements.append("<ContinuationToken>\(token)</ContinuationToken>")
    }
    if let token = page.nextContinuationToken {
      elements.append("<NextContinuationToken>\(token)</NextContinuationToken>")
    }
    for element in elements { #expect(xml.contains(element), "\(element)") }
    #expect(
      xml.components(separatedBy: "<CommonPrefixes>").count - 1 == page.prefixes.count)
    #expect(xml.components(separatedBy: "<Contents>").count - 1 == page.objects.count)
    #expect(xml.contains("<Delimiter>") == (page.delimiter != nil))
  }

  /// An object entry; directory validation examines only the key, so other fields are synthetic.
  static func object(_ key: String) -> BulkObject {
    BulkObject(
      eTag: "\"d41d8cd98f00b204e9800998ecf8427e\"", key: key,
      lastModified: "2021-02-27T02:56:26.000Z", size: 0, storageClass: "STANDARD")
  }
}

extension CatalogBulkRequest where Response == BulkDirectoryPage {
  fileprivate static func threeRecordGroups() throws -> Self {
    .directory(try BulkDirectoryQuery(directory: .recordGroups, maxKeys: 3))
  }
}
