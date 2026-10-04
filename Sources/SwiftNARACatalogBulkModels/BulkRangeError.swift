/// A refused range request or inconsistent partial representation.
public enum BulkRangeError: Error, Hashable, Sendable {
  /// Bounds are negative, reversed, overflowing, or start beyond the known object.
  case invalidRange
  /// The key, strong entity tag, known length or optional version is invalid.
  case invalidReference
  /// Status, range syntax, encoding or received interval does not match the request.
  case invalidResponse
  /// The server returned a whole 200 response to a range request; no bytes are published.
  case rangeNotHonored
  /// A validator, known total length or pinned version changed or was omitted.
  case representationChanged
}
