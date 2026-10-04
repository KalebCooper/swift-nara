/// One inclusive byte interval, without a suffix, open end, or multipart selection.
public struct DigitalObjectByteRange: Hashable, Sendable {
  /// The first requested byte, starting at zero.
  public let lowerBound: Int64
  /// The last requested byte, inclusive.
  public let upperBound: Int64

  /// Number of requested bytes before clipping to the known end of the representation.
  public var byteCount: Int64 { upperBound - lowerBound + 1 }
  /// The exact single-range HTTP field value.
  public var headerValue: String { "bytes=\(lowerBound)-\(upperBound)" }

  /// Creates an interval without I/O.
  /// - Parameters:
  ///   - lowerBound: Nonnegative first byte offset.
  ///   - upperBound: Inclusive last offset, at least the first.
  /// - Throws: `DigitalObjectRangeError.invalidRange` for negative, reversed or overflowing bounds.
  public init(lowerBound: Int64, upperBound: Int64) throws(DigitalObjectRangeError) {
    guard lowerBound >= 0, upperBound >= lowerBound, upperBound - lowerBound < Int64.max else {
      throw .invalidRange
    }
    self.lowerBound = lowerBound
    self.upperBound = upperBound
  }

  package func clipped(to totalByteCount: Int64) throws(DigitalObjectRangeError) -> Self {
    guard totalByteCount > lowerBound else { throw .invalidRange }
    return try Self(lowerBound: lowerBound, upperBound: min(upperBound, totalByteCount - 1))
  }

  static func decimal(_ text: Substring) -> Int64? {
    guard !text.isEmpty, text.utf8.allSatisfy({ $0 >= 48 && $0 <= 57 }) else { return nil }
    return Int64(text)
  }
}
