#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// The portable UTF-8 codec for NARA's S3 ListObjectsV2 responses.
///
/// This source-specific parser has no FoundationXML or external entity dependency. It accepts
/// namespaces, escaped text, comments, and CDATA; rejects DTDs, external entities, malformed XML,
/// duplicate scalar fields, and non-S3 roots. Unknown fields remain available in source receipts.
public enum ManifestCodec {
  /// Reads a complete S3 listing within an explicit input bound.
  /// - Parameters:
  ///   - data: Original UTF-8 XML bytes.
  ///   - maximumBytes: Maximum document bytes; defaults to 4 MiB.
  /// - Returns: Objects and exact opaque continuation metadata in source order.
  /// - Throws: `CatalogDecodingError.limitExceeded` for size/depth limits, or `.malformedXML`.
  public static func decode(_ data: Data, maximumBytes: Int = 4 * 1024 * 1024)
    throws(CatalogDecodingError) -> BulkManifest
  {
    guard maximumBytes > 0, data.count <= maximumBytes else { throw .limitExceeded }
    var parser = S3XMLParser(bytes: Array(data))
    let root = try parser.document()
    guard root.name == "ListBucketResult",
      root.namespace == "" || root.namespace == "http://s3.amazonaws.com/doc/2006-03-01/"
    else { throw .malformedXML }
    let encoding = try root.optional("EncodingType")
    guard encoding == nil || encoding == "url", try root.optional("Delimiter") == nil,
      !root.children.contains(where: { $0.name == "CommonPrefixes" })
    else { throw .malformedXML }
    func key(_ value: String) throws(CatalogDecodingError) -> String {
      guard encoding == "url" else { return value }
      guard let decoded = Endpoint<BulkManifest>.decoded(value) else { throw .malformedXML }
      return decoded
    }
    let truncated = try root.required("IsTruncated")
    guard truncated == "true" || truncated == "false",
      let count = Int(try root.required("KeyCount")), count >= 0,
      let maxKeys = Int(try root.required("MaxKeys")), (1...1000).contains(maxKeys)
    else { throw .malformedXML }
    var objects: [BulkObject] = []
    for child in root.children where child.name == "Contents" {
      guard child.namespace == root.namespace,
        let size = Int64(try child.required("Size")), size >= 0
      else { throw .malformedXML }
      objects.append(
        BulkObject(
          eTag: try child.required("ETag"), key: try key(child.required("Key")),
          lastModified: try child.required("LastModified"), size: size,
          storageClass: try child.optional("StorageClass")))
    }
    guard count == objects.count, count <= maxKeys else { throw .malformedXML }
    return BulkManifest(
      continuationToken: try root.optional("ContinuationToken"), isTruncated: truncated == "true",
      keyCount: count, maxKeys: maxKeys, name: try root.required("Name"),
      nextContinuationToken: try root.optional("NextContinuationToken"), objects: objects,
      prefix: try key(root.required("Prefix")))
  }
}

private struct S3XMLNode {
  var children: [S3XMLNode] = []
  let name: String
  let namespace: String
  var text = ""

  func optional(_ name: String) throws(CatalogDecodingError) -> String? {
    let matches = children.filter { $0.name == name }
    guard matches.count <= 1 else { throw .malformedXML }
    guard let match = matches.first else { return nil }
    guard match.namespace == namespace, match.children.isEmpty else { throw .malformedXML }
    return match.text
  }

  func required(_ name: String) throws(CatalogDecodingError) -> String {
    guard let value = try optional(name) else { throw .malformedXML }
    return value
  }
}

private struct S3XMLParser {
  let bytes: [UInt8]
  var index = 0
  var nodes = 0

  mutating func comment() throws(CatalogDecodingError) {
    try take("<!--")
    let content = try through("-->")
    guard !content.contains("--"), !content.hasSuffix("-") else { throw .malformedXML }
  }

  mutating func document() throws(CatalogDecodingError) -> S3XMLNode {
    guard String(bytes: bytes, encoding: .utf8) != nil,
      !bytes.contains(where: { $0 < 32 && $0 != 9 && $0 != 10 && $0 != 13 })
    else { throw .malformedXML }
    if starts([239, 187, 191]) { index += 3 }
    whitespace()
    if starts(Array("<?xml ".utf8)) {
      let declaration = try through("?>")
      // The S3 distribution is UTF-8. Other encodings must not be misinterpreted.
      guard
        !declaration.lowercased().contains("encoding") || declaration.lowercased().contains("utf-8")
      else { throw .malformedXML }
    }
    try trivia()
    let root = try element(depth: 0, namespaces: [:])
    try trivia()
    guard index == bytes.count else { throw .malformedXML }
    return root
  }

  mutating func element(depth: Int, namespaces inherited: [String: String])
    throws(CatalogDecodingError) -> S3XMLNode
  {
    guard depth < 16, nodes < 50000 else { throw .limitExceeded }
    nodes += 1
    try take("<")
    let qualified = try name()
    var attributes: [String: String] = [:]
    var namespaces = inherited
    while true {
      let before = index
      whitespace()
      if starts(Array("/>".utf8)) || starts([62]) { break }
      guard index > before else { throw .malformedXML }
      let attribute = try name()
      guard attributes[attribute] == nil else { throw .malformedXML }
      whitespace(); try take("="); whitespace()
      guard index < bytes.count, bytes[index] == 34 || bytes[index] == 39 else {
        throw .malformedXML
      }
      let quote = bytes[index]; index += 1
      let begin = index
      while index < bytes.count && bytes[index] != quote {
        guard bytes[index] != 60 else { throw .malformedXML }; index += 1
      }
      guard index < bytes.count else { throw .malformedXML }
      let value = try unescape(Array(bytes[begin..<index])); index += 1
      attributes[attribute] = value
      if attribute == "xmlns" {
        namespaces[""] = value
      } else if attribute.hasPrefix("xmlns:") {
        namespaces[String(attribute.dropFirst(6))] = value
      }
    }
    let parts = qualified.split(separator: ":", omittingEmptySubsequences: false)
    guard parts.count <= 2, parts.allSatisfy({ !$0.isEmpty }) else { throw .malformedXML }
    let prefix = parts.count == 2 ? String(parts[0]) : ""
    guard prefix.isEmpty || namespaces[prefix] != nil else { throw .malformedXML }
    var node = S3XMLNode(name: String(parts[parts.count - 1]), namespace: namespaces[prefix] ?? "")
    if starts(Array("/>".utf8)) { index += 2; return node }
    try take(">")
    while index < bytes.count {
      if starts(Array("</".utf8)) {
        index += 2
        guard try name() == qualified else { throw .malformedXML }
        whitespace(); try take(">")
        return node
      } else if starts(Array("<!--".utf8)) {
        try comment()
      } else if starts(Array("<![CDATA[".utf8)) {
        index += 9; node.text += try through("]]>")
      } else if starts([60]) {
        node.children.append(try element(depth: depth + 1, namespaces: namespaces))
      } else {
        let begin = index
        while index < bytes.count && bytes[index] != 60 { index += 1 }
        let content = Array(bytes[begin..<index])
        guard !String(decoding: content, as: UTF8.self).contains("]]>") else { throw .malformedXML }
        node.text += try unescape(content)
      }
    }
    throw .malformedXML
  }

  mutating func name() throws(CatalogDecodingError) -> String {
    let begin = index
    while index < bytes.count {
      let b = bytes[index]
      guard
        (65...90).contains(b) || (97...122).contains(b) || b == 95 || b == 58
          || (index > begin && ((48...57).contains(b) || b == 45 || b == 46))
      else { break }
      index += 1
    }
    guard index > begin else { throw .malformedXML }
    return String(decoding: bytes[begin..<index], as: UTF8.self)
  }

  func starts(_ value: [UInt8]) -> Bool { bytes[index...].starts(with: value) }

  mutating func take(_ value: String) throws(CatalogDecodingError) {
    guard starts(Array(value.utf8)) else { throw .malformedXML }
    index += value.utf8.count
  }

  mutating func through(_ end: String) throws(CatalogDecodingError) -> String {
    let begin = index
    let suffix = Array(end.utf8)
    while index < bytes.count && !starts(suffix) { index += 1 }
    guard index < bytes.count else { throw .malformedXML }
    let value = String(decoding: bytes[begin..<index], as: UTF8.self)
    index += suffix.count
    return value
  }

  mutating func trivia() throws(CatalogDecodingError) {
    whitespace()
    while starts(Array("<!--".utf8)) { try comment(); whitespace() }
  }

  func unescape(_ input: [UInt8]) throws(CatalogDecodingError) -> String {
    var result = ""
    var position = 0
    while position < input.count {
      let begin = position
      while position < input.count && input[position] != 38 { position += 1 }
      result += String(decoding: input[begin..<position], as: UTF8.self)
      guard position < input.count else { break }
      position += 1
      let start = position
      while position < input.count && input[position] != 59 { position += 1 }
      guard position < input.count else { throw .malformedXML }
      let entity = String(decoding: input[start..<position], as: UTF8.self)
      position += 1
      switch entity {
      case "amp": result += "&"
      case "apos": result += "'"
      case "gt": result += ">"
      case "lt": result += "<"
      case "quot": result += "\""
      default:
        let hex = entity.hasPrefix("#x")
        guard entity.hasPrefix("#"),
          let code = UInt32(entity.dropFirst(hex ? 2 : 1), radix: hex ? 16 : 10),
          code == 9 || code == 10 || code == 13 || (code >= 32 && code <= 0xD7FF)
            || (code >= 0xE000 && code <= 0xFFFD) || (code >= 0x10000 && code <= 0x10FFFF),
          let scalar = UnicodeScalar(code)
        else { throw .malformedXML }
        result.unicodeScalars.append(scalar)
      }
    }
    return result
  }

  mutating func whitespace() {
    while index < bytes.count && [9, 10, 13, 32].contains(bytes[index]) { index += 1 }
  }
}
