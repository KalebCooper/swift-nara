#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// Open JSON data that preserves unknown members and distinguishes null from absence.
///
/// Original JSONL bytes remain the authority for exact numeric spelling and whitespace.
public indirect enum JSONValue: Codable, Hashable, Sendable {
  /// An ordered JSON array.
  case array([JSONValue])
  /// A JSON Boolean.
  case bool(Bool)
  /// A signed integral number, without floating-point conversion.
  case integer(Int64)
  /// An explicit JSON null.
  case null
  /// A finite nonintegral or out-of-range JSON number.
  case number(Double)
  /// A JSON object including all unknown fields.
  case object([String: JSONValue])
  /// A JSON string.
  case string(String)
  /// An unsigned number outside the signed range.
  case unsignedInteger(UInt64)

  /// Decodes an open JSON value.
  public init(from decoder: any Decoder) throws {
    let value = try decoder.singleValueContainer()
    if value.decodeNil() {
      self = .null
    } else if let result = try? value.decode(Bool.self) {
      self = .bool(result)
    } else if let result = try? value.decode(Int64.self) {
      self = .integer(result)
    } else if let result = try? value.decode(UInt64.self) {
      self = .unsignedInteger(result)
    } else if let result = try? value.decode(Double.self) {
      self = .number(result)
    } else if let result = try? value.decode(String.self) {
      self = .string(result)
    } else if let result = try? value.decode([JSONValue].self) {
      self = .array(result)
    } else {
      self = .object(try value.decode([String: JSONValue].self))
    }
  }

  /// The array contents, or nil for another JSON kind.
  public var array: [JSONValue]? { if case .array(let value) = self { value } else { nil } }
  /// A source identifier represented as a string or an exact integer.
  public var identifier: String? {
    switch self {
    case .integer(let value): String(value)
    case .string(let value): value
    case .unsignedInteger(let value): String(value)
    default: nil
    }
  }
  /// The object members, or nil for another JSON kind.
  public var object: [String: JSONValue]? {
    if case .object(let value) = self { value } else { nil }
  }
  /// The string contents, or nil for another JSON kind.
  public var string: String? { if case .string(let value) = self { value } else { nil } }

  /// Returns an object member without collapsing explicit null into absence.
  public subscript(_ key: String) -> JSONValue? { object?[key] }

  /// Encodes all retained JSON fields.
  public func encode(to encoder: any Encoder) throws {
    var target = encoder.singleValueContainer()
    switch self {
    case .array(let value): try target.encode(value)
    case .bool(let value): try target.encode(value)
    case .integer(let value): try target.encode(value)
    case .null: try target.encodeNil()
    case .number(let value): try target.encode(value)
    case .object(let value): try target.encode(value)
    case .string(let value): try target.encode(value)
    case .unsignedInteger(let value): try target.encode(value)
    }
  }
}
