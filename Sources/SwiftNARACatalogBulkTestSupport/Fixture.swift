import Foundation

/// Official source captures; exact requests, instants, headers, sizes, and hashes are in attribution.json.
package enum Fixture: String, CaseIterable {
  /// descriptions/collections/coll_FDR-FDRMSF/coll_FDR-FDRMSF-1.jsonl, unchanged.
  case fdr = "fdr.jsonl"
  /// ListObjectsV2 for descriptions/record-groups/rg_11/, max-keys=4.
  case manifestFirst = "manifest-first.xml"
  /// The same listing with the first response's exact continuation token.
  case manifestSecond = "manifest-second.xml"
  /// ListObjectsV2 for descriptions/collections/coll_FDR-FDRMSF/, max-keys=1000.
  case manifestTerminal = "manifest-terminal.xml"
  /// descriptions/record-groups/rg_11/rg_11-1.jsonl, unchanged.
  case rg11 = "rg11.jsonl"

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
