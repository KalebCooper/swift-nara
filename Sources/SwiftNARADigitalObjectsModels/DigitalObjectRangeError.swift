/// A refused range request or inconsistent partial representation.
public enum DigitalObjectRangeError: Error, Hashable, Sendable {
  /// Bounds are negative, reversed, overflowing, or start beyond the known object.
  case invalidRange
  /// The strong entity tag or known whole-object length is invalid.
  case invalidReference
  /// Status, range syntax, encoding or received interval does not match the request.
  case invalidResponse
  /// The server returned a whole 200 response to a range request; no bytes are published.
  case rangeNotHonored
  /// The validator or known total length changed or was omitted.
  case representationChanged
}
