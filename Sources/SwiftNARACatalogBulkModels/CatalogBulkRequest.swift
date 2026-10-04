/// A reusable bulk operation with an inspectable value resolution.
///
/// ```swift
/// let request = CatalogBulkRequest.manifest(try ManifestQuery(prefix: "descriptions/"))
/// ```
public struct CatalogBulkRequest<Response>: Hashable, Sendable {
  /// The operation to execute, with no transport closure or hidden I/O.
  public enum Resolution: Hashable, Sendable {
    /// A built-in directory listing query with validated continuation semantics.
    case directory(BulkDirectoryQuery)
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

extension CatalogBulkRequest where Response == BulkDirectoryPage {
  /// Describes a directory listing lookup or independent lazy traversal.
  ///
  /// ```swift
  /// let request = CatalogBulkRequest.directory(try BulkDirectoryQuery(directory: .collections))
  /// ```
  /// - Parameter query: The initial query.
  /// - Returns: A request with built-in continuation validation.
  public static func directory(_ query: BulkDirectoryQuery) -> Self {
    Self(resolution: .directory(query))
  }
}

extension CatalogBulkRequest where Response == BulkManifest {
  /// Describes a manifest lookup or independent lazy traversal.
  /// - Parameter query: The initial query.
  /// - Returns: A request with built-in continuation validation.
  public static func manifest(_ query: ManifestQuery) -> Self { Self(resolution: .manifest(query)) }
}

extension CatalogBulkRequest where Response == BulkRangeReceipt {
  /// Describes one validated byte-range transfer without a destination or construction I/O.
  /// - Parameters:
  ///   - range: Inclusive requested interval.
  ///   - reference: The known source representation.
  /// - Returns: A reusable partial-download request.
  public static func range(_ range: BulkByteRange, of reference: BulkRangeReference) -> Self {
    Self(endpoint: .range(range, of: reference))
  }
}

extension CatalogBulkRequest where Response == ShardReceipt {
  /// Describes a streamed JSONL download, independently of its destination file.
  /// - Parameter reference: The selected object and optional version.
  /// - Returns: An immutable shard request.
  public static func shard(_ reference: ShardReference) -> Self {
    Self(endpoint: .shard(reference))
  }
}

extension CatalogBulkRequest where Response == ShardRefreshResult {
  /// Describes a conditional JSONL download, independently of its destination file.
  ///
  /// The request resolves to ``CatalogBulkRequest/Resolution/endpoint(_:)`` with the same endpoint as
  /// ``Endpoint/refresh(_:condition:)``.
  /// ```swift
  /// let request = CatalogBulkRequest.refresh(reference, condition: try .ifNoneMatch(previousETag))
  /// ```
  /// - Parameters:
  ///   - reference: The selected object and optional version.
  ///   - condition: The single validator the executor sends with the download.
  /// - Returns: An immutable conditional shard request.
  public static func refresh(_ reference: ShardReference, condition: ShardCondition) -> Self {
    Self(endpoint: .refresh(reference, condition: condition))
  }
}
