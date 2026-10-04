/// The result of comparing a previous and a current `BulkObject` version hint.
///
/// The comparison is pure and looks only at the two supplied values: it opens no connection and
/// consults no stored inventory. Unchanged hints mean no observed metadata change, not verified
/// byte identity; S3 can serve identical bytes under a new ETag, and this comparison cannot tell
/// the two cases apart. A changed hint is evidence to refetch, not proof the bytes differ.
public enum BulkObjectChange: Hashable, Sendable {
  /// At least one compared field differs between the previous and current object.
  case changed(fields: Fields)
  /// There is no previous object to compare against.
  case noPriorEvidence
  /// Every compared field matches between the previous and current object.
  case unchangedHints
}

extension BulkObjectChange {
  /// The compared `BulkObject` fields that differed.
  ///
  /// A key difference means the two objects describe different keys, so any other differing
  /// field is not evidence about one object's history; `compare(previous:current:)` still reports
  /// it, since the comparison observes and does not decide on a consumer's behalf.
  public struct Fields: OptionSet, Hashable, Sendable {
    /// The underlying option bits.
    public let rawValue: Int

    /// Creates a field set from its raw option bits.
    public init(rawValue: Int) {
      self.rawValue = rawValue
    }

    /// The `eTag` values differ.
    public static let eTag = Fields(rawValue: 1 << 0)
    /// The `key` values differ.
    public static let key = Fields(rawValue: 1 << 1)
    /// The `lastModified` values differ.
    public static let lastModified = Fields(rawValue: 1 << 2)
    /// The `size` values differ.
    public static let size = Fields(rawValue: 1 << 3)
  }
}

extension BulkObjectChange {
  /// Compares a previous and a current object hint by key, ETag, size, and last-modified.
  ///
  /// `storageClass` is not compared; it is not a version hint. This function performs no I/O and
  /// consults no stored inventory: it reports only what the two supplied values show.
  /// ```swift
  /// let change = BulkObjectChange.compare(previous: previousObject, current: currentObject)
  /// ```
  /// - Parameters:
  ///   - previous: The object hint from a prior inventory, or `nil` when none was recorded.
  ///   - current: The object hint from the latest listing.
  /// - Returns: `.noPriorEvidence` when `previous` is `nil`; otherwise `.unchangedHints` when
  ///   `key`, `eTag`, `size`, and `lastModified` all match, or `.changed(fields:)` naming every
  ///   field that differs.
  public static func compare(previous: BulkObject?, current: BulkObject) -> BulkObjectChange {
    guard let previous else {
      return .noPriorEvidence
    }
    var fields: Fields = []
    if previous.eTag != current.eTag {
      fields.insert(.eTag)
    }
    if previous.key != current.key {
      fields.insert(.key)
    }
    if previous.lastModified != current.lastModified {
      fields.insert(.lastModified)
    }
    if previous.size != current.size {
      fields.insert(.size)
    }
    return fields.isEmpty ? .unchangedHints : .changed(fields: fields)
  }
}
