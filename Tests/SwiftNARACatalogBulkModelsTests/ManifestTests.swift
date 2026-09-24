import Foundation
import SwiftNARACatalogBulkModels
import SwiftNARACatalogBulkTestSupport
import Testing

@Suite(.timeLimit(.minutes(suiteTimeLimitMinutes)))
struct ManifestTests {
  @Test("Captured listings preserve object order and opaque tokens")
  func capturedListingsPreserveObjectOrderAndOpaqueTokens() throws {
    let first = try BulkManifest.decode(Fixture.manifestFirst.data())
    let second = try BulkManifest.decode(Fixture.manifestSecond.data())
    let query = try ManifestQuery(maxKeys: 4, prefix: "descriptions/record-groups/rg_11/")
    let next = try #require(try query.next(after: first))
    #expect(first.objects.count == 4)
    #expect(first.objects[0].key == "descriptions/record-groups/rg_11/rg_11-1.jsonl")
    #expect(first.objects[1].key == "descriptions/record-groups/rg_11/rg_11-10.jsonl")
    #expect(next.continuationToken == second.continuationToken)
    #expect(try next.next(after: second)?.continuationToken == second.nextContinuationToken)
    #expect(Endpoint.manifest(next).path.contains("%2B"))
    #expect(Endpoint.manifest(next).path.contains("%2F"))
    let terminal = try BulkManifest.decode(Fixture.manifestTerminal.data())
    #expect(terminal.objects.count == 395)
    #expect(
      try ManifestQuery(prefix: "descriptions/collections/coll_FDR-FDRMSF/").next(after: terminal)
        == nil)
  }

  @Test("Endpoint validation rejects another origin and path confusion")
  func endpointValidationRejectsAnotherOriginAndPathConfusion() throws {
    for path in [
      "//evil.test/a", "/descriptions/../a", "/descriptions/%2e%2e/a", "/descriptions/a%2fb",
      "/descriptions/a%5Cb", "/descriptions/a%", "/descriptions/a#b", "/api/v2/records",
      "/descriptions/a%00",
    ] {
      #expect(Endpoint<BulkManifest>(path: path) == nil, "\(path)")
    }
    for link in [
      "http://nara-national-archives-catalog.s3.amazonaws.com/", "https://evil.test/",
      "https://user@nara-national-archives-catalog.s3.amazonaws.com/",
      "https://nara-national-archives-catalog.s3.amazonaws.com:444/",
    ] {
      #expect(Endpoint<BulkManifest>(link: try #require(URL(string: link))) == nil)
    }
    let shard = try ShardReference(key: "descriptions/a b+%.jsonl", versionID: "v+/=")
    #expect(Endpoint.shard(shard).path == "/descriptions/a%20b%2B%25.jsonl?versionId=v%2B%2F%3D")
    #expect(throws: ManifestError.invalidQuery) {
      try ShardReference(key: "descriptions/../x.jsonl")
    }
    #expect(throws: ManifestError.invalidQuery) { try ManifestQuery(maxKeys: 0) }
    #expect(throws: ManifestError.invalidQuery) { try ManifestQuery(maxKeys: 1001) }
    #expect(throws: ManifestError.invalidQuery) { try ManifestQuery(continuationToken: "") }
  }

  @Test("Malformed and hostile XML cannot become a successful page")
  func malformedAndHostileXMLCannotBecomeASuccessfulPage() throws {
    let data = try Fixture.manifestFirst.data()
    let xml = String(decoding: data, as: UTF8.self)
    let invalid = [
      xml + "<extra/>",
      xml.replacingOccurrences(of: "</Name>", with: "</Name><Name>duplicate</Name>"),
      xml.replacingOccurrences(of: "<KeyCount>4</KeyCount>", with: "<KeyCount>3</KeyCount>"),
      xml.replacingOccurrences(
        of: "<IsTruncated>true</IsTruncated>", with: "<IsTruncated>maybe</IsTruncated>"),
      "<!DOCTYPE ListBucketResult [<!ENTITY external SYSTEM 'file:///etc/passwd'>]>" + xml,
      xml.replacingOccurrences(
        of: "nara-national-archives-catalog</Name>", with: "&external;</Name>"),
      String(repeating: "<x>", count: 17) + String(repeating: "</x>", count: 17),
    ]
    for input in invalid {
      #expect(throws: CatalogDecodingError.self) { try ManifestCodec.decode(Data(input.utf8)) }
    }
    #expect(throws: CatalogDecodingError.limitExceeded) {
      try ManifestCodec.decode(data, maximumBytes: data.count - 1)
    }
  }

  @Test("Namespaces and escaped key text decode portably")
  func namespacesAndEscapedKeyTextDecodePortably() throws {
    let xml = """
      <?xml version="1.0" encoding="UTF-8"?>
      <!-- source-specific synthetic namespace and entity coverage -->
      <s:ListBucketResult xmlns:s="http://s3.amazonaws.com/doc/2006-03-01/">
      <s:Name>nara-national-archives-catalog</s:Name><s:Prefix></s:Prefix>
      <s:MaxKeys>1</s:MaxKeys><s:KeyCount>1</s:KeyCount><s:IsTruncated>false</s:IsTruncated>
      <s:Contents><s:Key>descriptions/A&amp;B&#x20;é.jsonl</s:Key><s:Size>0</s:Size>
      <s:LastModified><![CDATA[2026-04-09T00:00:00.000Z]]></s:LastModified><s:ETag>&quot;opaque-2&quot;</s:ETag></s:Contents>
      </s:ListBucketResult>
      """
    let page = try BulkManifest.decode(Data(xml.utf8))
    #expect(page.objects[0].key == "descriptions/A&B é.jsonl")
    #expect(page.objects[0].eTag == "\"opaque-2\"")
    #expect(page.objects[0].size == 0)
  }

  @Test("Truncated pages require progress and consistent query metadata")
  func truncatedPagesRequireProgressAndConsistentQueryMetadata() throws {
    let page = try BulkManifest.decode(Fixture.manifestFirst.data())
    let query = try ManifestQuery(maxKeys: 4, prefix: "descriptions/record-groups/rg_11/")
    let missing = BulkManifest(
      isTruncated: true, keyCount: 4, maxKeys: 4, name: page.name, objects: page.objects,
      prefix: page.prefix)
    #expect(throws: ManifestError.missingContinuation) { try query.next(after: missing) }
    let repeated = BulkManifest(
      continuationToken: "same", isTruncated: true, keyCount: 4, maxKeys: 4, name: page.name,
      nextContinuationToken: "same", objects: page.objects, prefix: page.prefix)
    #expect(throws: ManifestError.repeatedContinuation) {
      try ManifestQuery(continuationToken: "same", maxKeys: 4, prefix: page.prefix).next(
        after: repeated)
    }
    #expect(throws: ManifestError.inconsistentPage) {
      try ManifestQuery(maxKeys: 3, prefix: page.prefix).next(after: page)
    }
  }
}
