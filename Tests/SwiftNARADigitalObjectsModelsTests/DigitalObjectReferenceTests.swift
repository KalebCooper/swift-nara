import Foundation
import SwiftNARADigitalObjectsModels
import SwiftNARADigitalObjectsTestSupport
import Testing

@Suite(.timeLimit(.minutes(suiteTimeLimitMinutes)))
struct DigitalObjectReferenceTests {
  /// fdr.jsonl line 1, NAID 122178160, objectId 122178162.
  static let fdrPageURL =
    "https://s3.amazonaws.com/NARAprodstorage/lz/presidential-libraries/roosevelt/577534/msf00611_Page_01.jpg"
  /// rg11.jsonl line 3, NAID 63545805, objectId 63545806.
  static let rg11LiveURL =
    "https://s3.amazonaws.com/NARAprodstorage/opastorage/live/5/5458/63545805/content/TB149/M1518/M1518_0007/images/0065.jpg"
  /// rg11.jsonl line 11, NAID 100358199, objectId 114274029.
  static let rg11LandingZoneURL =
    "https://s3.amazonaws.com/NARAprodstorage/lz/dc-metro/rg-011/299798/100358199/100358199-001_ac.jpg"

  static func reference(_ url: String) throws(DigitalObjectReferenceError) -> DigitalObjectReference
  {
    try DigitalObjectReference(naID: "122178160", objectID: "122178162", url: url)
  }

  @Test("A bulk landing zone URL maps to the public medialz path")
  func aBulkLandingZoneURLMapsToThePublicMedialzPath() throws {
    let fdr = try DigitalObjectReference(
      naID: "122178160", objectID: "122178162", url: Self.fdrPageURL)
    #expect(fdr.naID == "122178160")
    #expect(fdr.objectID == "122178162")
    #expect(
      fdr.url
        == "https://s3.amazonaws.com/NARAprodstorage/lz/presidential-libraries/roosevelt/577534/msf00611_Page_01.jpg"
    )
    #expect(
      fdr.transportPath == "/medialz/presidential-libraries/roosevelt/577534/msf00611_Page_01.jpg")
    #expect(
      fdr.transportURL.absoluteString
        == "https://catalog.archives.gov/medialz/presidential-libraries/roosevelt/577534/msf00611_Page_01.jpg"
    )

    let rg11 = try DigitalObjectReference(
      naID: "100358199", objectID: "114274029", url: Self.rg11LandingZoneURL)
    #expect(rg11.naID == "100358199")
    #expect(rg11.objectID == "114274029")
    #expect(
      rg11.url
        == "https://s3.amazonaws.com/NARAprodstorage/lz/dc-metro/rg-011/299798/100358199/100358199-001_ac.jpg"
    )
    #expect(rg11.transportPath == "/medialz/dc-metro/rg-011/299798/100358199/100358199-001_ac.jpg")
  }

  @Test("A bulk live storage URL maps to the public medialive path")
  func aBulkLiveStorageURLMapsToThePublicMedialivePath() throws {
    let reference = try DigitalObjectReference(
      naID: "63545805", objectID: "63545806", url: Self.rg11LiveURL)
    #expect(
      reference.url
        == "https://s3.amazonaws.com/NARAprodstorage/opastorage/live/5/5458/63545805/content/TB149/M1518/M1518_0007/images/0065.jpg"
    )
    #expect(
      reference.transportPath
        == "/medialive/5/5458/63545805/content/TB149/M1518/M1518_0007/images/0065.jpg")
    #expect(
      reference.transportURL.absoluteString
        == "https://catalog.archives.gov/medialive/5/5458/63545805/content/TB149/M1518/M1518_0007/images/0065.jpg"
    )
  }

  @Test("An already public URL keeps its path")
  func anAlreadyPublicURLKeepsItsPath() throws {
    let landingZone = try Self.reference(
      "https://catalog.archives.gov/medialz/presidential-libraries/roosevelt/577534/msf00611_Page_01.jpg"
    )
    #expect(
      landingZone.transportPath
        == "/medialz/presidential-libraries/roosevelt/577534/msf00611_Page_01.jpg")
    #expect(
      landingZone.url
        == "https://catalog.archives.gov/medialz/presidential-libraries/roosevelt/577534/msf00611_Page_01.jpg"
    )
    let live = try Self.reference(
      "https://catalog.archives.gov/medialive/5/5458/63545805/content/TB149/M1518/M1518_0007/images/0065.jpg"
    )
    #expect(
      live.transportPath
        == "/medialive/5/5458/63545805/content/TB149/M1518/M1518_0007/images/0065.jpg")
  }

  @Test("A missing object identifier is preserved as nil")
  func aMissingObjectIdentifierIsPreservedAsNil() throws {
    let reference = try DigitalObjectReference(
      naID: "122178160", objectID: nil, url: Self.fdrPageURL)
    #expect(reference.objectID == nil)
    #expect(reference.naID == "122178160")
  }

  @Test("Percent escapes in the remainder are carried over unchanged")
  func percentEscapesInTheRemainderAreCarriedOverUnchanged() throws {
    // Synthetic: no recorded bulk URL contains a percent escape.
    let reference = try Self.reference(
      "https://s3.amazonaws.com/NARAprodstorage/lz/a%20b/caf%C3%A9.jpg")
    #expect(reference.transportPath == "/medialz/a%20b/caf%C3%A9.jpg")
    #expect(reference.url == "https://s3.amazonaws.com/NARAprodstorage/lz/a%20b/caf%C3%A9.jpg")
  }

  @Test("An unparseable or inexactly spelled URL is malformed")
  func anUnparseableOrInexactlySpelledURLIsMalformed() {
    // Synthetic refusals.
    for url in [
      "https://catalog.archives.gov/medialz/a b.jpg",
      "https://catalog.archives.gov/medialz/a[1].jpg",
      "https://catalog.archives.gov/medialz/a%zz.jpg",
      "https://catalog.archives.gov/medialz/a%+f.jpg",
      "https://catalog.archives.gov/medialz/a%2",
      "https://catalog.archives.gov:/medialz/a.jpg",
    ] {
      #expect(throws: DigitalObjectReferenceError.malformedURL) { try Self.reference(url) }
    }
  }

  @Test("A scheme other than https is refused")
  func aSchemeOtherThanHttpsIsRefused() {
    // Synthetic refusals.
    for url in [
      "http://catalog.archives.gov/medialz/a.jpg",
      "http://s3.amazonaws.com/NARAprodstorage/lz/a.jpg",
      "HTTPS://catalog.archives.gov/medialz/a.jpg",
      "ftp://s3.amazonaws.com/NARAprodstorage/lz/a.jpg",
      "catalog.archives.gov/medialz/a.jpg",
    ] {
      #expect(throws: DigitalObjectReferenceError.unsupportedScheme) { try Self.reference(url) }
    }
  }

  @Test("User information is refused")
  func userInformationIsRefused() {
    // Synthetic refusals.
    for url in [
      "https://user@catalog.archives.gov/medialz/a.jpg",
      "https://user:secret@s3.amazonaws.com/NARAprodstorage/lz/a.jpg",
      "https://:secret@catalog.archives.gov/medialz/a.jpg",
      "https://@catalog.archives.gov/medialz/a.jpg",
    ] {
      #expect(throws: DigitalObjectReferenceError.userInfo) { try Self.reference(url) }
    }
  }

  @Test("Any other host or any explicit port is refused")
  func anyOtherHostOrAnyExplicitPortIsRefused() {
    // Synthetic refusals, except the first, which is the Catalog schema's objectUrl example.
    for url in [
      "https://nara-media-001.s3.amazonaws.com/arcmedia/media/images/16/16/16-1557a.gif",
      "https://s3.us-east-1.amazonaws.com/NARAprodstorage/lz/a.jpg",
      "https://s3.dualstack.us-east-1.amazonaws.com/NARAprodstorage/lz/a.jpg",
      "https://NARAprodstorage.s3.amazonaws.com/lz/a.jpg",
      "https://nara-national-archives-catalog.s3.amazonaws.com/descriptions/a.jpg",
      "https://CATALOG.ARCHIVES.GOV/medialz/a.jpg",
      "https://catalog.archives.gov./medialz/a.jpg",
      "https://catalog.archives.gov:443/medialz/a.jpg",
      "https://s3.amazonaws.com:8443/NARAprodstorage/lz/a.jpg",
      "https:///medialz/a.jpg",
    ] {
      #expect(throws: DigitalObjectReferenceError.unsupportedOrigin) { try Self.reference(url) }
    }
  }

  @Test("A fragment is refused")
  func aFragmentIsRefused() {
    // Synthetic refusals.
    for url in [
      "https://catalog.archives.gov/medialz/a.jpg#page=2",
      "https://s3.amazonaws.com/NARAprodstorage/lz/a.jpg#",
    ] {
      #expect(throws: DigitalObjectReferenceError.fragment) { try Self.reference(url) }
    }
  }

  @Test("A query is refused")
  func aQueryIsRefused() {
    // Synthetic refusals.
    for url in [
      "https://catalog.archives.gov/medialz/a.jpg?download=1",
      "https://s3.amazonaws.com/NARAprodstorage/lz/a.jpg?",
    ] {
      #expect(throws: DigitalObjectReferenceError.query) { try Self.reference(url) }
    }
  }

  @Test("A path outside the accepted prefixes is refused")
  func aPathOutsideTheAcceptedPrefixesIsRefused() {
    // Synthetic refusals.
    for url in [
      "https://catalog.archives.gov/id/122178160",
      "https://catalog.archives.gov/medialz",
      "https://catalog.archives.gov/MEDIALZ/a.jpg",
      "https://s3.amazonaws.com/NARAprodstorage/opastorage/a.jpg",
      "https://s3.amazonaws.com/NARAprodstorage/other/a.jpg",
      "https://s3.amazonaws.com/naraprodstorage/lz/a.jpg",
      "https://s3.amazonaws.com/medialz/a.jpg",
      "https://catalog.archives.gov/NARAprodstorage/lz/a.jpg",
      "https://s3.amazonaws.com",
    ] {
      #expect(throws: DigitalObjectReferenceError.unsupportedPath) { try Self.reference(url) }
    }
  }

  @Test("A prefix with nothing after it is refused")
  func aPrefixWithNothingAfterItIsRefused() {
    // Synthetic refusals.
    for url in [
      "https://catalog.archives.gov/medialive/",
      "https://catalog.archives.gov/medialz/",
      "https://s3.amazonaws.com/NARAprodstorage/lz/",
      "https://s3.amazonaws.com/NARAprodstorage/opastorage/live/",
    ] {
      #expect(throws: DigitalObjectReferenceError.emptyRemainder) { try Self.reference(url) }
    }
  }

  @Test("A literal or encoded dot segment is refused")
  func aLiteralOrEncodedDotSegmentIsRefused() {
    // Synthetic refusals.
    for url in [
      "https://catalog.archives.gov/medialz/../secret.jpg",
      "https://catalog.archives.gov/medialive/./a.jpg",
      "https://s3.amazonaws.com/NARAprodstorage/lz/a/%2e%2E/b.jpg",
      "https://s3.amazonaws.com/NARAprodstorage/lz/a/.%2E/b.jpg",
      "https://s3.amazonaws.com/NARAprodstorage/opastorage/live/%2E",
      "https://catalog.archives.gov/medialz/a//../b.jpg",
    ] {
      #expect(throws: DigitalObjectReferenceError.traversal) { try Self.reference(url) }
    }
  }

  @Test("An empty, encoded separator, control, or invalid segment is refused")
  func anEmptyEncodedSeparatorControlOrInvalidSegmentIsRefused() {
    // Synthetic refusals.
    for url in [
      "https://catalog.archives.gov/medialz/a//b.jpg",
      "https://catalog.archives.gov/medialz/a/",
      "https://catalog.archives.gov/medialz//a.jpg",
      "https://catalog.archives.gov/medialz/a%2Fb.jpg",
      "https://catalog.archives.gov/medialz/a%5Cb.jpg",
      "https://catalog.archives.gov/medialz/a%00.jpg",
      "https://catalog.archives.gov/medialz/a%7F.jpg",
      "https://catalog.archives.gov/medialz/a%FF.jpg",
    ] {
      #expect(throws: DigitalObjectReferenceError.malformedPath) { try Self.reference(url) }
    }
  }

  @Test("Encoding writes the identifiers and original URL only")
  func encodingWritesTheIdentifiersAndOriginalURLOnly() throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    let full = try DigitalObjectReference(
      naID: "122178160", objectID: "122178162", url: Self.fdrPageURL)
    #expect(
      String(decoding: try encoder.encode(full), as: UTF8.self)
        == #"{"naID":"122178160","objectID":"122178162","url":"https://s3.amazonaws.com/NARAprodstorage/lz/presidential-libraries/roosevelt/577534/msf00611_Page_01.jpg"}"#
    )
    let bare = try DigitalObjectReference(naID: "122178160", objectID: nil, url: Self.fdrPageURL)
    #expect(
      String(decoding: try encoder.encode(bare), as: UTF8.self)
        == #"{"naID":"122178160","url":"https://s3.amazonaws.com/NARAprodstorage/lz/presidential-libraries/roosevelt/577534/msf00611_Page_01.jpg"}"#
    )
  }

  @Test("Decoding derives the transport path and ignores a supplied one")
  func decodingDerivesTheTransportPathAndIgnoresASuppliedOne() throws {
    // Synthetic: the transportPath member is planted to show it is never read.
    let json = Data(
      #"{"naID":"63545805","objectID":null,"transportPath":"/elsewhere","url":"https://s3.amazonaws.com/NARAprodstorage/opastorage/live/5/5458/63545805/content/TB149/M1518/M1518_0007/images/0065.jpg"}"#
        .utf8)
    let reference = try JSONDecoder().decode(DigitalObjectReference.self, from: json)
    #expect(reference.naID == "63545805")
    #expect(reference.objectID == nil)
    #expect(
      reference.transportPath
        == "/medialive/5/5458/63545805/content/TB149/M1518/M1518_0007/images/0065.jpg")
    #expect(
      reference
        == (try DigitalObjectReference(naID: "63545805", objectID: nil, url: Self.rg11LiveURL)))
  }

  @Test("Decoding a refused URL fails with the typed case")
  func decodingARefusedURLFailsWithTheTypedCase() {
    // Synthetic: a URL outside the origin policy.
    let json = Data(
      #"{"naID":"122178160","url":"https://nara-media-001.s3.amazonaws.com/arcmedia/media/images/16/16/16-1557a.gif"}"#
        .utf8)
    do {
      _ = try JSONDecoder().decode(DigitalObjectReference.self, from: json)
      Issue.record("A refused URL decoded.")
    } catch {
      guard case .dataCorrupted(let context) = error as? DecodingError else {
        Issue.record("Expected DecodingError.dataCorrupted, got \(error).")
        return
      }
      #expect(context.codingPath.map(\.stringValue) == ["url"])
      #expect(context.underlyingError as? DigitalObjectReferenceError == .unsupportedOrigin)
    }
  }
}
