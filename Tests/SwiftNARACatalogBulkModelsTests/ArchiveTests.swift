import Foundation
import SwiftNARACatalogBulkModels
import SwiftNARACatalogBulkTestSupport
import Testing

@Suite(.timeLimit(.minutes(suiteTimeLimitMinutes)))
struct ArchiveTests {
  @Test(
    "Archive references preserve encoded identity without widening shard or raw endpoint policy")
  func identity() throws {
    let reference = try BulkArchiveReference(key: "zip/export space%.zip", versionID: "a+/=")
    let endpoint = Endpoint.archive(reference)
    let request = CatalogBulkRequest.archive(reference)
    #expect(endpoint.path == "/zip/export%20space%25.zip?versionId=a%2B%2F%3D")
    #expect(endpoint.archiveReference == reference)
    #expect(request.resolution == .endpoint(endpoint))
    #expect(Endpoint<ShardReceipt>(path: "/zip/example.zip") == nil)
    #expect(throws: ManifestError.self) { try ShardReference(key: "zip/example.zip") }
    #expect(
      try JSONDecoder().decode(BulkArchiveReference.self, from: JSONEncoder().encode(reference))
        == reference)
    let range = try reference.rangeReference(entityTag: "\"opaque\"", totalByteCount: 229)
    #expect(range.key == "zip/export space%.zip")
    #expect(range.versionID == "a+/=")
    #expect(range.totalByteCount == 229)
  }

  @Test("Invalid archive keys and decoded versions repeat validation")
  func invalidReferences() throws {
    for key in [
      "zip/", "zip/loose.jsonl", "descriptions/a.zip", "/zip/a.zip",
      "zip//a.zip", "zip/../a.zip", "zip/./a.zip", "zip/a\\b.zip", "zip/a\n.zip",
    ] {
      #expect(throws: ManifestError.self) { try BulkArchiveReference(key: key) }
    }
    for version in ["", "null", "bad\n"] {
      #expect(throws: ManifestError.self) {
        try BulkArchiveReference(key: "zip/a.zip", versionID: version)
      }
    }
    let invalid = Data("{\"key\":\"descriptions/a.zip\",\"versionID\":null}".utf8)
    #expect(throws: (any Error).self) {
      try JSONDecoder().decode(BulkArchiveReference.self, from: invalid)
    }
  }

  @Test(
    "Official bulk ZIP listings preserve old exports and loose JSONL entries without assuming latest"
  )
  func listings() throws {
    let page = try BulkManifest.decode(Fixture.manifestArchiveExports.data())
    #expect(page.objects.count == 10)
    #expect(page.isTruncated)
    #expect(page.objects.first?.key == "zip/nac_export_authorities_2021-08-22.zip")
    #expect(page.objects[7].key == "zip/nac_export_authorities_2026-09-14.zip")
    #expect(page.objects[7].size == 48_559_426)
    #expect(try ManifestQuery(maxKeys: 10, prefix: "zip/nac_export_").next(after: page) != nil)
    for object in page.objects { _ = try BulkArchiveReference(key: object.key) }
    let mixed = try BulkManifest.decode(Fixture.manifestArchives.data())
    #expect(mixed.objects.count == 10)
    #expect(mixed.objects.first?.key == "zip/")
    #expect(
      mixed.objects[1].key == "zip/authorities/geographic-reference/geographic-reference-1.jsonl")
    #expect(throws: ManifestError.self) { try BulkArchiveReference(key: mixed.objects[1].key) }
  }
}
