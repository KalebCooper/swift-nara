#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// A successfully completed local digital object download and its retrieval evidence.
///
/// A receipt records what was received and where it was saved; it performs no I/O. The
/// retrieval instant is supplied by the caller, normally from an injected clock, and is not a
/// publication or modification time. Header ETags are version hints, not content digests.
/// ``mediaType`` is read only from a received `Content-Type` field and is never inferred from
/// the URL, the saved bytes, or bulk metadata.
/// ```swift
/// let receipt = DigitalObjectReceipt(
///   byteCount: 65_981, fileURL: destination,
///   headers: [.init(name: "Content-Type", value: "image/jpeg")],
///   reference: reference, retrievedAt: retrievedAt, status: 200,
///   transportURL: reference.transportURL)
/// print(receipt.mediaType ?? "undeclared")  // image/jpeg
/// ```
public struct DigitalObjectReceipt: Codable, Hashable, Sendable {
  /// One received HTTP header field, as received.
  ///
  /// A receipt keeps its headers in received order, with duplicate field names preserved.
  /// ```swift
  /// let header = DigitalObjectReceipt.Header(name: "X-Cache", value: "Hit from cloudfront")
  /// ```
  public struct Header: Codable, Hashable, Sendable {
    /// The received field name, with its original case.
    public let name: String
    /// The received field value, unchanged.
    public let value: String

    /// Creates a received header field.
    /// - Parameters:
    ///   - name: The received field name.
    ///   - value: The received field value.
    public init(name: String, value: String) {
      self.name = name
      self.value = value
    }
  }

  /// The number of object bytes saved.
  public let byteCount: Int64
  /// The destination file holding the complete received bytes.
  public let fileURL: URL
  /// Every received header, in received order, with duplicate names preserved.
  public let headers: [Header]
  /// The reference the download was created from, or `nil` when its endpoint was created from
  /// a link with ``Endpoint/init(link:)``, which carries no National Archives Identifier or
  /// object identifier.
  public let reference: DigitalObjectReference?
  /// The caller-supplied instant the response was received.
  public let retrievedAt: Date
  /// The received HTTP status.
  public let status: Int
  /// The exact URL requested on ``Endpoint/origin``.
  public let transportURL: URL

  /// The value of the first received `Content-Type` field, or `nil` when no such field was
  /// received.
  ///
  /// The field name is matched without regard to case. The value is returned unchanged,
  /// parameters included, as in `text/html; charset=utf-8`. An absent field stays `nil`; no
  /// media type is guessed.
  public var mediaType: String? {
    headers.first { $0.name.lowercased() == "content-type" }?.value
  }

  /// Creates a receipt for a supplied local file and its known retrieval evidence.
  /// - Parameters:
  ///   - byteCount: The number of object bytes saved.
  ///   - fileURL: The destination file holding the complete received bytes.
  ///   - headers: Every received header, in received order.
  ///   - reference: The reference the download was created from, or `nil` for a link.
  ///   - retrievedAt: The instant the response was received.
  ///   - status: The received HTTP status.
  ///   - transportURL: The exact URL requested.
  public init(
    byteCount: Int64, fileURL: URL, headers: [Header], reference: DigitalObjectReference?,
    retrievedAt: Date, status: Int, transportURL: URL
  ) {
    self.byteCount = byteCount
    self.fileURL = fileURL
    self.headers = headers
    self.reference = reference
    self.retrievedAt = retrievedAt
    self.status = status
    self.transportURL = transportURL
  }
}
