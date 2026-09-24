/// A reusable bulk operation with an inspectable value resolution.
///
/// ```swift
/// let request = CatalogBulkRequest.manifest(try ManifestQuery(prefix: "descriptions/"))
/// ```
public struct CatalogBulkRequest<Response>: Hashable, Sendable {
  /// The operation to execute, with no transport closure or hidden I/O.
  public enum Resolution: Hashable, Sendable {
    /// One consumer-defined endpoint, without automatic continuation.
    case endpoint(Endpoint<Response>)
    /// A built-in manifest query with validated continuation semantics.
    case manifest(ManifestQuery)
  }

  /// The complete operation description.
  public let resolution: Resolution

  /// Describes a consumer-defined endpoint without automatic pagination.
  /// - Parameter endpoint: The independently executable operation.
  public init(endpoint: Endpoint<Response>) { resolution = .endpoint(endpoint) }

  private init(resolution: Resolution) { self.resolution = resolution }
}

extension CatalogBulkRequest where Response == BulkManifest {
  /// Describes a manifest lookup or independent lazy traversal.
  /// - Parameter query: The initial query.
  /// - Returns: A request with built-in continuation validation.
  public static func manifest(_ query: ManifestQuery) -> Self { Self(resolution: .manifest(query)) }
}

extension CatalogBulkRequest where Response == ShardReceipt {
  /// Describes a streamed JSONL download, independently of its destination file.
  /// - Parameter reference: The selected object and optional version.
  /// - Returns: An immutable shard request.
  public static func shard(_ reference: ShardReference) -> Self {
    Self(endpoint: .shard(reference))
  }
}
