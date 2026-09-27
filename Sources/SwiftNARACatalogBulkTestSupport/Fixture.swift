import Foundation

/// Official source captures; exact requests, instants, headers, sizes, and hashes are in attribution.json.
package enum Fixture: String, CaseIterable {
  /// ListObjectsV2 for authority-records/, delimiter=/, max-keys=20.
  case directoryAuthorityRecords = "directory-authority-records.xml"
  /// ListObjectsV2 for authority-records/, max-keys=8, without a delimiter.
  case directoryAuthorityRecordsUndelimited = "directory-authority-records-undelimited.xml"
  /// ListObjectsV2 for descriptions/collections/, delimiter=/, max-keys=3.
  case directoryCollectionsFirst = "directory-collections-first.xml"
  /// The same listing with the first response's exact continuation token.
  case directoryCollectionsSecond = "directory-collections-second.xml"
  /// ListObjectsV2 for descriptions/record-groups/, delimiter=/, max-keys=3.
  case directoryRecordGroups = "directory-record-groups.xml"
  /// descriptions/collections/coll_FDR-FDRMSF/coll_FDR-FDRMSF-1.jsonl, unchanged.
  case fdr = "fdr.jsonl"
  /// authority-records/geographic-reference/geographic-reference-1.jsonl, unchanged.
  case geographicReference = "geographic-reference.jsonl"
  /// ListObjectsV2 for descriptions/record-groups/rg_11/, max-keys=4.
  case manifestFirst = "manifest-first.xml"
  /// The same listing with the first response's exact continuation token.
  case manifestSecond = "manifest-second.xml"
  /// ListObjectsV2 for descriptions/collections/coll_FDR-FDRMSF/, max-keys=1000.
  case manifestTerminal = "manifest-terminal.xml"
  /// authority-records/organization/organization-1.jsonl, unchanged.
  case organization = "organization.jsonl"
  /// authority-records/person/person-1.jsonl, unchanged.
  case person = "person.jsonl"
  /// Response headers of the 304 to a GET of descriptions/collections/coll_FDR-FDRMSF/coll_FDR-FDRMSF-1.jsonl
  /// with If-None-Match "4ee6006efb1a7923711c088aaf8626a0"; the response had no body.
  case refreshNotModified = "refresh-not-modified.headers.json"
  /// Body of the 412 to a GET of descriptions/collections/coll_FDR-FDRMSF/coll_FDR-FDRMSF-1.jsonl
  /// with If-Match "0000000000000000000000000000dead", unchanged.
  case refreshPreconditionFailed = "refresh-precondition-failed.xml"
  /// descriptions/record-groups/rg_11/rg_11-1.jsonl, unchanged.
  case rg11 = "rg11.jsonl"
  /// authority-records/specific-records-type/specific-records-type-1.jsonl, unchanged.
  case specificRecordsType = "specific-records-type.jsonl"
  /// authority-records/topical-subject/topical-subject-1.jsonl, unchanged.
  case topicalSubject = "topical-subject.jsonl"

  /// Loads one recorded body without a live request.
  package func data() throws -> Data { try Data(contentsOf: url()) }

  /// Locates the original fixture for independent local iteration.
  package func url() throws -> URL {
    guard
      let url = Bundle.module.url(
        forResource: rawValue, withExtension: nil, subdirectory: "Fixtures")
    else {
      throw CocoaError(.fileReadNoSuchFile)
    }
    return url
  }
}

/// All deterministic suites share this upper bound.
package let suiteTimeLimitMinutes = 1
