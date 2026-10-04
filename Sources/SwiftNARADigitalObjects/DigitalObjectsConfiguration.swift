/// Explicit caller identity and byte bounds for on-demand digital objects.
public struct DigitalObjectsConfiguration: Sendable {
  /// The maximum retained bytes for a substituted page or HTTP status failure.
  public let maximumErrorBodyBytes: Int
  /// The maximum buffered bytes for one IIIF information document.
  public let maximumInformationBytes: Int
  /// The maximum bytes accepted for one complete object.
  public let maximumObjectBytes: Int64
  /// The maximum bytes accepted for one range, independent of complete-object size.
  public let maximumRangeBytes: Int64
  /// The caller's application identity and contact information.
  public let userAgent: String

  /// Creates a configuration without inferred identity or download budgets.
  /// - Parameters:
  ///   - maximumErrorBodyBytes: A positive diagnostic-body limit.
  ///   - maximumInformationBytes: A positive information budget, defaulting to one MiB.
  ///   - maximumObjectBytes: A positive whole-object limit, independent of bulk metadata.
  ///   - maximumRangeBytes: Positive per-range bound, defaulting to four MiB.
  ///   - userAgent: A nonempty HTTP field value identifying the caller.
  /// - Throws: `DigitalObjectsError.invalidConfiguration` for invalid bounds or identity.
  public init(
    maximumErrorBodyBytes: Int, maximumInformationBytes: Int = 1_048_576, maximumObjectBytes: Int64,
    maximumRangeBytes: Int64 = 4 * 1024 * 1024, userAgent: String
  )
    throws(DigitalObjectsError)
  {
    guard maximumErrorBodyBytes > 0, maximumInformationBytes > 0, maximumObjectBytes > 0,
      maximumRangeBytes > 0,
      userAgent.contains(where: { !$0.isWhitespace }),
      !userAgent.unicodeScalars.contains(where: { $0.value < 32 || $0.value == 127 })
    else { throw .invalidConfiguration }
    self.maximumErrorBodyBytes = maximumErrorBodyBytes
    self.maximumInformationBytes = maximumInformationBytes
    self.maximumObjectBytes = maximumObjectBytes
    self.maximumRangeBytes = maximumRangeBytes
    self.userAgent = userAgent
  }
}
