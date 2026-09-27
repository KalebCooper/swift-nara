import Foundation
import SwiftNARACatalogBulkModels
import SwiftNARACatalogBulkTestSupport
import Testing

@Suite(.timeLimit(.minutes(suiteTimeLimitMinutes)))
struct RefreshTests {
  static let fdrKey = "descriptions/collections/coll_FDR-FDRMSF/coll_FDR-FDRMSF-1.jsonl"
  static let fdrPath = "/descriptions/collections/coll_FDR-FDRMSF/coll_FDR-FDRMSF-1.jsonl"
  static let fdrETag = "\"4ee6006efb1a7923711c088aaf8626a0\""
  static let fdrVersionID = "UJyiii_Crdud2H8tsuMrokVKx2zzjm.6"

  @Test("A refresh endpoint uses the shard path and carries its condition")
  func aRefreshEndpointUsesTheShardPathAndCarriesItsCondition() throws {
    let reference = try ShardReference(key: Self.fdrKey)
    let condition = try ShardCondition.ifNoneMatch(Self.fdrETag)
    let endpoint: Endpoint<ShardRefreshResult> = .refresh(reference, condition: condition)
    #expect(endpoint.path == Self.fdrPath)
    #expect(Endpoint.shard(reference).path == Self.fdrPath)
    #expect(endpoint.condition?.etag == "\"4ee6006efb1a7923711c088aaf8626a0\"")
    #expect(endpoint.condition?.kind == .ifNoneMatch)
    #expect(endpoint.condition?.fieldName == "If-None-Match")
    #expect(
      endpoint.url.absoluteString
        == "https://nara-national-archives-catalog.s3.amazonaws.com" + Self.fdrPath)
  }

  @Test("A refresh endpoint keeps the version pin and encoding of the shard path")
  func aRefreshEndpointKeepsTheVersionPinAndEncodingOfTheShardPath() throws {
    let pinned = try ShardReference(key: Self.fdrKey, versionID: Self.fdrVersionID)
    let condition = try ShardCondition.ifMatch(Self.fdrETag)
    let pinnedPath = Self.fdrPath + "?versionId=UJyiii_Crdud2H8tsuMrokVKx2zzjm.6"
    #expect(Endpoint.refresh(pinned, condition: condition).path == pinnedPath)
    #expect(Endpoint.shard(pinned).path == pinnedPath)
    // Synthetic key and version needing percent encoding.
    let encoded = try ShardReference(
      key: "descriptions/collections/coll_A B/x+y.jsonl", versionID: "v/1 2")
    let encodedPath = "/descriptions/collections/coll_A%20B/x%2By.jsonl?versionId=v%2F1%202"
    #expect(Endpoint.refresh(encoded, condition: condition).path == encodedPath)
    #expect(Endpoint.shard(encoded).path == encodedPath)
  }

  @Test("A refresh request resolves to the refresh endpoint")
  func aRefreshRequestResolvesToTheRefreshEndpoint() throws {
    let reference = try ShardReference(key: Self.fdrKey)
    let request = CatalogBulkRequest.refresh(reference, condition: try .ifNoneMatch(Self.fdrETag))
    let typed: CatalogBulkRequest<ShardRefreshResult> = request
    guard case .endpoint(let endpoint) = typed.resolution else {
      Issue.record("A refresh request resolves to one endpoint.")
      return
    }
    #expect(endpoint.path == Self.fdrPath)
    #expect(endpoint.condition == (try ShardCondition.ifNoneMatch(Self.fdrETag)))
    #expect(
      request.resolution
        == .endpoint(.refresh(reference, condition: try .ifNoneMatch(Self.fdrETag))))
  }

  @Test("Other endpoints carry no condition")
  func otherEndpointsCarryNoCondition() throws {
    let reference = try ShardReference(key: Self.fdrKey)
    #expect(Endpoint.shard(reference).condition == nil)
    #expect(Endpoint.manifest(try ManifestQuery(prefix: "descriptions/")).condition == nil)
    #expect(Endpoint<ShardRefreshResult>(path: Self.fdrPath)?.condition == nil)
  }

  @Test("A condition keeps the entity tag text exactly")
  func aConditionKeepsTheEntityTagTextExactly() throws {
    let recorded = try JSONDecoder().decode(
      [String: String].self, from: Fixture.refreshNotModified.data())
    let etag = try #require(recorded["ETag"])
    #expect(try ShardCondition.ifNoneMatch(etag).etag == "\"4ee6006efb1a7923711c088aaf8626a0\"")
    // Synthetic weak and unquoted entity tags.
    #expect(try ShardCondition.ifMatch("W/\"abc\"").etag == "W/\"abc\"")
    #expect(try ShardCondition.ifMatch("abc").etag == "abc")
    #expect(try ShardCondition.ifMatch("\"a b\"").etag == "\"a b\"")
    let condition = try ShardCondition(etag: "\"x\"", kind: .ifMatch)
    #expect(condition.etag == "\"x\"")
    #expect(condition.kind == .ifMatch)
    #expect(condition.fieldName == "If-Match")
  }

  @Test("Conditions compare and hash by kind and exact entity tag")
  func conditionsCompareAndHashByKindAndExactEntityTag() throws {
    let first = try ShardCondition.ifNoneMatch(Self.fdrETag)
    let second = try ShardCondition(
      etag: "\"4ee6006efb1a7923711c088aaf8626a0\"", kind: .ifNoneMatch)
    #expect(first == second)
    #expect(first.hashValue == second.hashValue)
    #expect(first != (try ShardCondition.ifMatch(Self.fdrETag)))
    #expect(first != (try ShardCondition.ifNoneMatch("4ee6006efb1a7923711c088aaf8626a0")))
    #expect(first != (try ShardCondition.ifNoneMatch("W/\"4ee6006efb1a7923711c088aaf8626a0\"")))
    let set: Set<ShardCondition> = [
      first, second, try .ifMatch(Self.fdrETag), try .ifNoneMatch("\"other\""),
    ]
    #expect(set.count == 3)
    let reference = try ShardReference(key: Self.fdrKey)
    let endpoints: Set<Endpoint<ShardRefreshResult>> = [
      .refresh(reference, condition: first), .refresh(reference, condition: second),
      .refresh(reference, condition: try .ifMatch(Self.fdrETag)),
    ]
    #expect(endpoints.count == 2)
  }

  @Test("Invalid entity tags are rejected")
  func invalidEntityTagsAreRejected() {
    let invalid = [
      "", "*", "\"a\", \"b\"", "\"a\",", " \"a\"", "\"a\" ", "\t\"a\"", "\"a\"\t", "\u{0}",
      "\"a\"\n", "\"a\"\r\n", "\"a\u{1F}\"", "\"a\"\u{7F}",
    ]
    for etag in invalid {
      for kind in [ShardCondition.Kind.ifMatch, .ifNoneMatch] {
        do {
          _ = try ShardCondition(etag: etag, kind: kind)
          Issue.record("An invalid entity tag was accepted.")
        } catch {
          #expect(error == .invalidQuery)
        }
      }
      #expect(throws: ManifestError.invalidQuery) { try ShardCondition.ifMatch(etag) }
      #expect(throws: ManifestError.invalidQuery) { try ShardCondition.ifNoneMatch(etag) }
    }
  }

  @Test("Refresh results keep their evidence through coding")
  func refreshResultsKeepTheirEvidenceThroughCoding() throws {
    let url = try #require(
      URL(string: "https://nara-national-archives-catalog.s3.amazonaws.com" + Self.fdrPath))
    let headers = [
      SourceHeader(name: "ETag", value: "\"4ee6006efb1a7923711c088aaf8626a0\""),
      SourceHeader(name: "x-amz-version-id", value: "UJyiii_Crdud2H8tsuMrokVKx2zzjm.6"),
    ]
    let retrieval = SourceRetrieval(
      headers: headers, retrievedAt: Date(timeIntervalSince1970: 1_790_462_863), status: 304,
      url: url)
    let notModified = ShardRefreshResult.notModified(retrieval)
    guard case .notModified(let kept) = notModified else {
      Issue.record("A not-modified result keeps its retrieval.")
      return
    }
    #expect(kept.status == 304)
    #expect(kept.headers == headers)
    let fileURL = URL(fileURLWithPath: "/synthetic/fdr.jsonl")
    let downloaded = ShardRefreshResult.downloaded(
      ShardReceipt(
        byteCount: 12,
        fileURL: fileURL,
        retrieval: SourceRetrieval(
          headers: headers, retrievedAt: Date(timeIntervalSince1970: 1_790_462_863), status: 200,
          url: url)))
    guard case .downloaded(let receipt) = downloaded else {
      Issue.record("A downloaded result keeps its receipt.")
      return
    }
    #expect(receipt.byteCount == 12)
    #expect(receipt.fileURL == fileURL)
    #expect(receipt.retrieval.status == 200)
    #expect(notModified != downloaded)
    for result in [notModified, downloaded] {
      let decoded = try JSONDecoder().decode(
        ShardRefreshResult.self, from: JSONEncoder().encode(result))
      #expect(decoded == result)
    }
  }

  static let rg11First = BulkObject(
    eTag: "\"c21eded7d1711eb3cbd549778015c49e\"",
    key: "descriptions/record-groups/rg_11/rg_11-1.jsonl",
    lastModified: "2026-04-09T12:49:55.000Z", size: 417_823,
    storageClass: "INTELLIGENT_TIERING")
  static let rg11Tenth = BulkObject(
    eTag: "\"bf33cb95e15d9262a3237b444197e9bc\"",
    key: "descriptions/record-groups/rg_11/rg_11-10.jsonl",
    lastModified: "2026-04-09T12:49:55.000Z", size: 442_978,
    storageClass: "INTELLIGENT_TIERING")

  @Test("There is no prior evidence when there is no previous object")
  func thereIsNoPriorEvidenceWhenThereIsNoPreviousObject() {
    #expect(BulkObjectChange.compare(previous: nil, current: Self.rg11First) == .noPriorEvidence)
  }

  @Test("Hints are unchanged when every compared field matches")
  func hintsAreUnchangedWhenEveryComparedFieldMatches() {
    #expect(
      BulkObjectChange.compare(previous: Self.rg11First, current: Self.rg11First)
        == .unchangedHints)
  }

  @Test("A storage-class difference alone is not a compared field")
  func aStorageClassDifferenceAloneIsNotAComparedField() {
    // Synthetic: same key, ETag, size, and last-modified; only storageClass differs.
    let recompacted = BulkObject(
      eTag: Self.rg11First.eTag, key: Self.rg11First.key,
      lastModified: Self.rg11First.lastModified, size: Self.rg11First.size,
      storageClass: "STANDARD")
    #expect(
      BulkObjectChange.compare(previous: Self.rg11First, current: recompacted)
        == .unchangedHints)
  }

  @Test("A changed entity tag is reported")
  func aChangedEntityTagIsReported() {
    // Synthetic: rg11First with rg11Tenth's ETag, everything else unchanged.
    let retagged = BulkObject(
      eTag: Self.rg11Tenth.eTag, key: Self.rg11First.key,
      lastModified: Self.rg11First.lastModified, size: Self.rg11First.size,
      storageClass: Self.rg11First.storageClass)
    #expect(
      BulkObjectChange.compare(previous: Self.rg11First, current: retagged)
        == .changed(fields: [.eTag]))
  }

  @Test("A changed size is reported")
  func aChangedSizeIsReported() {
    // Synthetic: rg11First with rg11Tenth's size, everything else unchanged.
    let resized = BulkObject(
      eTag: Self.rg11First.eTag, key: Self.rg11First.key,
      lastModified: Self.rg11First.lastModified, size: Self.rg11Tenth.size,
      storageClass: Self.rg11First.storageClass)
    #expect(
      BulkObjectChange.compare(previous: Self.rg11First, current: resized)
        == .changed(fields: [.size]))
  }

  @Test("A changed last-modified timestamp is reported")
  func aChangedLastModifiedTimestampIsReported() {
    // Synthetic: rg11First with a later last-modified timestamp, everything else unchanged.
    let retimed = BulkObject(
      eTag: Self.rg11First.eTag, key: Self.rg11First.key,
      lastModified: "2026-04-10T00:00:00.000Z", size: Self.rg11First.size,
      storageClass: Self.rg11First.storageClass)
    #expect(
      BulkObjectChange.compare(previous: Self.rg11First, current: retimed)
        == .changed(fields: [.lastModified]))
  }

  @Test("Multiple changed fields are reported together")
  func multipleChangedFieldsAreReportedTogether() {
    // Synthetic: rg11First with rg11Tenth's ETag and size, everything else unchanged.
    let retaggedAndResized = BulkObject(
      eTag: Self.rg11Tenth.eTag, key: Self.rg11First.key,
      lastModified: Self.rg11First.lastModified, size: Self.rg11Tenth.size,
      storageClass: Self.rg11First.storageClass)
    #expect(
      BulkObjectChange.compare(previous: Self.rg11First, current: retaggedAndResized)
        == .changed(fields: [.eTag, .size]))
  }

  @Test("A key mismatch still reports every other differing field")
  func aKeyMismatchStillReportsEveryOtherDifferingField() {
    #expect(
      BulkObjectChange.compare(previous: Self.rg11First, current: Self.rg11Tenth)
        == .changed(fields: [.eTag, .key, .size]))
  }
}
