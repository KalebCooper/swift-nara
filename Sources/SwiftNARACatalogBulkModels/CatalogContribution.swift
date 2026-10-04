#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// One public contribution, such as a comment, tag, or transcription, exported alongside a
/// Catalog record.
///
/// Contributions come from the top-level `record_comment`, `record_tag`, and
/// `record_transcription` arrays of a bulk envelope, not from the `record` object. They are
/// community or staff contributions attributed to Catalog users. They are not the archival
/// creators or contributors of the holding, which remain in the record's own members, and a
/// contributor is never matched to a president, member, or other identity.
///
/// Contribution text is contributed text. It is not certified original text, and it is not the
/// source OCR: a transcription never replaces or updates a digital object's `extractedText`, and
/// neither one is a certified copy of the original document. The export can carry several
/// contributions for one page, for different pages, or with the same sequence number; nothing is
/// merged, deduplicated, reordered, or treated as a revision history beyond the exported entries.
///
/// ```swift
/// for try await line in try CatalogLineSequence(shard: receipt) {
///   for transcription in line.record.transcriptions ?? [] {
///     print(transcription.contributionSource?.rawValue, transcription.isAIMachineGenerated)
///     print(transcription.target?.objectID, transcription.target?.pageNumber)
///     print(transcription.contribution ?? "")
///   }
/// }
/// ```
///
/// Tags and comments name a single `contributor` object; transcriptions list a `contributors`
/// array with each contributor's own sequence and time. Both are retained unchanged. All source
/// members, including unknown ones, remain in `source`, and `CatalogLine.rawBytes` remains the
/// byte-exact authority. Absent, null, and wrong-shaped members project to nil; inspect `source` to
/// distinguish them.
public struct CatalogContribution: Codable, Hashable, Sendable {
  /// Every source member of the contribution, or the non-object value the source supplied instead.
  public let source: JSONValue
  /// Creates a projection over any source value without changing it.
  ///
  /// - Parameter source: The source contribution value; a non-object projects every member as nil.
  public init(source: JSONValue) { self.source = source }
  /// The contributed text, such as a comment, a tag, or a page transcription, only when the source
  /// supplies a string.
  ///
  /// The text is attributed to its contributors. It is not certified original text and is not
  /// source OCR.
  public var contribution: String? { source["contribution"]?.string }
  /// The exact source contribution identifier from `contributionId`.
  public var contributionID: String? { source["contributionId"]?.identifier }
  /// The source contribution sequence from `contributionSequence`, only when it is an exact
  /// integer.
  ///
  /// The sequence orders contributions in relation to a parent contribution. The recorded exports
  /// repeat sequence values within one record, so a sequence is not an identifier or a position.
  public var contributionSequence: Int? { source["contributionSequence"]?.exactInteger }
  /// The source attribution category from the contribution's own `source` member, only when it is a
  /// string.
  ///
  /// The recorded exports supply `communityMember` and `naraStaff`. Other values are retained
  /// exactly.
  public var contributionSource: CatalogContributionSource? {
    source["source"]?.string.map(CatalogContributionSource.init(rawValue:))
  }
  /// The source contribution type, such as `comment`, `tag`, or `transcription`, only when the
  /// source supplies a string.
  ///
  /// The value is the source's own statement; it is not checked against the array that held the
  /// contribution.
  public var contributionType: String? { source["contributionType"]?.string }
  /// The source contributor of a tag or comment, unchanged.
  ///
  /// In the recorded exports the object carries `fullName`, `naraStaff`, `userId`, and `userName`.
  /// It identifies a Catalog user, not an archival creator.
  public var contributor: JSONValue? { source["contributor"] }
  /// The source contributors of a transcription, unchanged and in source order, only when the
  /// source supplies an array.
  ///
  /// In the recorded exports each element carries `contributionSequence`, `createdAt`, `fullName`,
  /// `naraStaff`, `userId`, and `userName`. Elements identify Catalog users, not archival creators.
  public var contributors: [JSONValue]? { source["contributors"]?.array }
  /// The source creation time string from `createdAt`, unchanged and not parsed.
  ///
  /// The recorded exports spell it without a time zone, such as `2019-12-26 20:23:15`.
  public var createdAt: String? { source["createdAt"]?.string }
  /// The source `aiMachineGenerated` flag, only when the source supplies a Boolean.
  ///
  /// Nil means the member is absent, null, or another shape; it does not mean the text was written
  /// by a person. Inspect `source` to distinguish them.
  public var isAIMachineGenerated: Bool? {
    if case .bool(let value) = source["aiMachineGenerated"] { value } else { nil }
  }
  /// The exact source parent contribution identifier from `parentContributionId`.
  public var parentContributionID: String? { source["parentContributionId"]?.identifier }
  /// The source record type, such as `contribution`, only when the source supplies a string.
  public var recordType: String? { source["recordType"]?.string }
  /// The source target, only when the source supplies an object.
  public var target: CatalogContributionTarget? {
    guard let value = source["target"], value.object != nil else { return nil }
    return CatalogContributionTarget(source: value)
  }
  /// The source update time string from `updatedAt`, unchanged and not parsed.
  ///
  /// The recorded exports supply it on comments only.
  public var updatedAt: String? { source["updatedAt"]?.string }
}

/// The source metadata arrays exported alongside a record's contributions.
///
/// The bulk envelope carries `metadata_comment`, `metadata_tag`, and `metadata_transcription`
/// arrays next to the matching contribution arrays. In the recorded exports each element carries
/// `controlGroup`, `fileName`, `ingestTime`, and `uuid`. The arrays are kept separate and
/// unchanged: no element is joined to a contribution by position, because the source states no
/// correspondence rule.
///
/// ```swift
/// let metadata = record.contributionMetadata
/// print(metadata.transcriptions?.count, record.transcriptions?.count)
/// ```
///
/// Absent, null, and wrong-shaped arrays project to nil; inspect `source` to distinguish them.
public struct CatalogContributionMetadata: Codable, Hashable, Sendable {
  /// The entire source envelope that holds the metadata arrays.
  public let source: JSONValue
  /// Creates a projection over any source envelope without changing it.
  ///
  /// - Parameter source: The source envelope; a non-object projects every array as nil.
  public init(source: JSONValue) { self.source = source }
  /// The source `metadata_comment` elements, unchanged and in source order.
  public var comments: [JSONValue]? { source["metadata_comment"]?.array }
  /// The source `metadata_tag` elements, unchanged and in source order.
  public var tags: [JSONValue]? { source["metadata_tag"]?.array }
  /// The source `metadata_transcription` elements, unchanged and in source order.
  public var transcriptions: [JSONValue]? { source["metadata_transcription"]?.array }
}

/// An extensible Catalog contribution attribution category.
///
/// The constants name the values the Catalog bulk exports contain in a contribution's `source`
/// member. The provider can supply others, and every value is retained exactly in `rawValue`.
///
/// ```swift
/// let category = CatalogContributionSource(rawValue: "naraStaff")
/// print(category == .naraStaff)
/// ```
public struct CatalogContributionSource: Codable, Hashable, RawRepresentable, Sendable {
  /// The Catalog bulk `communityMember` attribution category.
  public static let communityMember = Self(rawValue: "communityMember")

  /// The Catalog bulk `naraStaff` attribution category.
  public static let naraStaff = Self(rawValue: "naraStaff")

  /// The source's exact attribution category string.
  public let rawValue: String

  /// Creates an attribution category without restricting future provider values.
  ///
  /// - Parameter rawValue: The exact attribution category string.
  public init(rawValue: String) { self.rawValue = rawValue }

  /// Decodes the exact attribution category string.
  ///
  /// - Parameter decoder: The decoder to read.
  /// - Throws: `DecodingError` for a non-string value.
  public init(from decoder: any Decoder) throws {
    rawValue = try decoder.singleValueContainer().decode(String.self)
  }

  /// Encodes the exact attribution category string.
  ///
  /// - Parameter encoder: The encoder to write.
  /// - Throws: Any error from the encoder.
  public func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(rawValue)
  }
}

/// The description, authority, or digital object a contribution is attached to.
///
/// The target keeps the exact identifiers the source supplies. The recorded exports supply a
/// `naId` on every target and an `objectId` and `pageNum` only for contributions attached to a
/// digital object or page. Nothing is fetched, and the target need not exist in any file that has
/// been read.
///
/// ```swift
/// if let target = transcription.target {
///   print(target.naID, target.objectID, target.pageNumber)
/// }
/// ```
///
/// All source members, including unknown ones, remain in `source`. Absent, null, and wrong-shaped
/// members project to nil; inspect `source` to distinguish them.
public struct CatalogContributionTarget: Codable, Hashable, Sendable {
  /// Every source member of the target, or the non-object value the source supplied instead.
  public let source: JSONValue
  /// Creates a projection over any source value without changing it.
  ///
  /// - Parameter source: The source target value; a non-object projects every member as nil.
  public init(source: JSONValue) { self.source = source }
  /// The exact National Archives identifier, without floating-point conversion.
  public var naID: String? { source["naId"]?.identifier }
  /// The exact source digital-object identifier from `objectId`.
  public var objectID: String? { source["objectId"]?.identifier }
  /// The source page number from `pageNum`, only when it is an exact integer.
  ///
  /// The page number is the source's own statement. The recorded exports repeat a page number for
  /// different objects within one record, so a page number does not identify an object.
  public var pageNumber: Int? { source["pageNum"]?.exactInteger }
}
