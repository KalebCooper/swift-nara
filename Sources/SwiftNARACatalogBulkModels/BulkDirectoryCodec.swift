#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// The portable UTF-8 codec for NARA's S3 ListObjectsV2 responses that group keys by delimiter.
///
/// It shares `ManifestCodec`'s source-specific parser and its rejections: DTDs, external
/// entities, malformed XML, duplicate scalar fields, non-S3 roots, and inputs past the size or
/// depth bound. It additionally reads an optional `/` delimiter and each `CommonPrefixes` entry.
/// A listing without a delimiter decodes with no prefixes; `BulkDirectoryQuery` still refuses to
/// continue from it. Unknown fields remain available in source receipts.
/// ```swift
/// let page = try BulkDirectoryCodec.decode(data)
/// print(page.prefixes)
/// ```
public enum BulkDirectoryCodec {
  /// Reads a complete S3 directory listing within an explicit input bound.
  /// - Parameters:
  ///   - data: Original UTF-8 XML bytes.
  ///   - maximumBytes: Maximum document bytes; defaults to 4 MiB.
  /// - Returns: Common prefixes and objects, each group in source order, with exact opaque
  ///   continuation metadata.
  /// - Throws: `CatalogDecodingError.limitExceeded` for size or depth limits, or
  ///   `CatalogDecodingError.malformedXML` for invalid XML, a delimiter other than `/`, a
  ///   `CommonPrefixes` entry without exactly one `Prefix`, prefixes without a delimiter, or a
  ///   key count that differs from the prefixes and objects listed.
  public static func decode(_ data: Data, maximumBytes: Int = 4 * 1024 * 1024)
    throws(CatalogDecodingError) -> BulkDirectoryPage
  {
    guard maximumBytes > 0, data.count <= maximumBytes else { throw .limitExceeded }
    var parser = S3XMLParser(bytes: Array(data))
    let root = try parser.document()
    guard root.name == "ListBucketResult",
      root.namespace == "" || root.namespace == "http://s3.amazonaws.com/doc/2006-03-01/"
    else { throw .malformedXML }
    let encoding = try root.optional("EncodingType")
    guard encoding == nil || encoding == "url" else { throw .malformedXML }
    func key(_ value: String) throws(CatalogDecodingError) -> String {
      guard encoding == "url" else { return value }
      guard let decoded = Endpoint<BulkDirectoryPage>.decoded(value) else { throw .malformedXML }
      return decoded
    }
    let delimiter = try root.optional("Delimiter").map { value throws(CatalogDecodingError) in
      try key(value)
    }
    let truncated = try root.required("IsTruncated")
    guard delimiter == nil || delimiter == "/", truncated == "true" || truncated == "false",
      let count = Int(try root.required("KeyCount")), count >= 0,
      let maxKeys = Int(try root.required("MaxKeys")), (1...1000).contains(maxKeys)
    else { throw .malformedXML }
    var objects: [BulkObject] = []
    var prefixes: [String] = []
    for child in root.children {
      switch child.name {
      case "CommonPrefixes":
        guard delimiter != nil, child.namespace == root.namespace, child.children.count == 1
        else { throw .malformedXML }
        prefixes.append(try key(child.required("Prefix")))
      case "Contents":
        guard child.namespace == root.namespace,
          let size = Int64(try child.required("Size")), size >= 0
        else { throw .malformedXML }
        objects.append(
          BulkObject(
            eTag: try child.required("ETag"), key: try key(child.required("Key")),
            lastModified: try child.required("LastModified"), size: size,
            storageClass: try child.optional("StorageClass")))
      default:
        continue
      }
    }
    guard count == objects.count + prefixes.count, count <= maxKeys else { throw .malformedXML }
    return BulkDirectoryPage(
      continuationToken: try root.optional("ContinuationToken"), delimiter: delimiter,
      isTruncated: truncated == "true", keyCount: count, maxKeys: maxKeys,
      name: try root.required("Name"),
      nextContinuationToken: try root.optional("NextContinuationToken"), objects: objects,
      prefix: try key(root.required("Prefix")), prefixes: prefixes)
  }
}
