#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// A digital object URL outside the verified source-to-transport mapping.
///
/// ``DigitalObjectReference`` throws exactly one case for each refused URL, before any request
/// exists. No case falls back to another origin or rewrites the input.
/// ```swift
/// do {
///   _ = try DigitalObjectReference(
///     naID: "122178160", objectID: nil, url: "http://catalog.archives.gov/medialz/a.jpg")
/// } catch {
///   print(error == .unsupportedScheme)  // true
/// }
/// ```
public enum DigitalObjectReferenceError: Error, Hashable, Sendable {
  /// The path ends at its accepted prefix and names no object, as in
  /// `https://catalog.archives.gov/medialz/`.
  case emptyRemainder
  /// The URL has a fragment, including an empty one after a trailing `#`.
  case fragment
  /// A path segment after the accepted prefix is empty, or decodes to a separator (`/` or `\`),
  /// a control character, or bytes that are not UTF-8, as with `%2F`, `%00`, or `%FF`. A doubled
  /// or trailing slash is an empty segment.
  ///
  /// A segment holding a character outside the URL path set or a malformed percent escape is
  /// also refused here if URL parsing accepted it; parsing normally refuses both first, as
  /// ``malformedURL``.
  case malformedPath
  /// The string does not parse as a URL, as with a space, a bracket, or a malformed percent
  /// escape such as `%zz`, or its parsed scheme, host, and path do not spell the input exactly,
  /// as with an empty port after the host.
  case malformedURL
  /// The URL has a query, including an empty one after a trailing `?`.
  case query
  /// A path segment after the accepted prefix is `.` or `..`, literally or percent-encoded in
  /// any case, such as `%2e%2E`.
  case traversal
  /// The host is not exactly `s3.amazonaws.com` or `catalog.archives.gov`, or the URL states
  /// any port, `:443` included.
  ///
  /// Regional (`s3.us-east-1.amazonaws.com`), dualstack, and virtual-hosted
  /// (`NARAprodstorage.s3.amazonaws.com`) bucket spellings are refused here until a bulk export
  /// evidences them. Host comparison is exact, so uppercase spellings are refused too.
  case unsupportedOrigin
  /// The host is accepted, but the path does not begin with one of its accepted prefixes:
  /// `/NARAprodstorage/lz/` or `/NARAprodstorage/opastorage/live/` on `s3.amazonaws.com`, and
  /// `/medialz/` or `/medialive/` on `catalog.archives.gov`. Prefix comparison is exact and
  /// case-sensitive.
  case unsupportedPath
  /// The scheme is not exactly `https`.
  case unsupportedScheme
  /// The URL carries a user name or password, even an empty one.
  case userInfo
}
