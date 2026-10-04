/// Explicit caller identity and byte bounds for on-demand digital objects.
public struct DigitalObjectsConfiguration: Sendable {
  /// The maximum retained bytes for a substituted page or HTTP status failure.
  public let maximumErrorBodyBytes: Int
  /// The maximum bytes accepted for one complete object.
  public let maximumObjectBytes: Int64
  /// The caller's application identity and contact information.
  public let userAgent: String

  /// Creates a configuration without inferred identity or download budgets.
  /// - Parameters:
  ///   - maximumErrorBodyBytes: A positive diagnostic-body limit.
  ///   - maximumObjectBytes: A positive whole-object limit, independent of bulk metadata.
  ///   - userAgent: A nonempty HTTP field value identifying the caller.
  /// - Throws: `DigitalObjectsError.invalidConfiguration` for invalid bounds or identity.
  public init(maximumErrorBodyBytes: Int, maximumObjectBytes: Int64, userAgent: String)
    throws(DigitalObjectsError)
  {
    guard maximumErrorBodyBytes > 0, maximumObjectBytes > 0,
      userAgent.contains(where: { !$0.isWhitespace }),
      !userAgent.unicodeScalars.contains(where: { $0.value < 32 || $0.value == 127 })
    else { throw .invalidConfiguration }
    self.maximumErrorBodyBytes = maximumErrorBodyBytes
    self.maximumObjectBytes = maximumObjectBytes
    self.userAgent = userAgent
  }
}
