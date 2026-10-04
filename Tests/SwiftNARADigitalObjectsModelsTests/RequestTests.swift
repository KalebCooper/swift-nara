import Foundation
import SwiftNARADigitalObjectsModels
import SwiftNARADigitalObjectsTestSupport
import Testing

@Suite(.timeLimit(.minutes(suiteTimeLimitMinutes)))
struct RequestTests {
  /// fdr.jsonl line 1, NAID 122178160, objectId 122178162.
  static let fdrPageURL =
    "https://s3.amazonaws.com/NARAprodstorage/lz/presidential-libraries/roosevelt/577534/msf00611_Page_01.jpg"
  /// rg11.jsonl line 3, NAID 63545805, objectId 63545806.
  static let rg11LiveURL =
    "https://s3.amazonaws.com/NARAprodstorage/opastorage/live/5/5458/63545805/content/TB149/M1518/M1518_0007/images/0065.jpg"
  /// 2026-09-27T13:52:22Z, the recorded retrieval second of the FDR page.
  static let retrievedAt = Date(timeIntervalSince1970: 1_790_517_142)

  static func fdrPage() throws -> DigitalObjectReference {
    try DigitalObjectReference(naID: "122178160", objectID: "122178162", url: fdrPageURL)
  }

  static func receipt(
    headers: [DigitalObjectReceipt.Header], reference: DigitalObjectReference?
  ) throws -> DigitalObjectReceipt {
    DigitalObjectReceipt(
      byteCount: 65_981, fileURL: URL(filePath: "/tmp/msf00611_Page_01.jpg"), headers: headers,
      reference: reference, retrievedAt: retrievedAt, status: 200,
      transportURL: try #require(
        URL(
          string:
            "https://catalog.archives.gov/medialz/presidential-libraries/roosevelt/577534/msf00611_Page_01.jpg"
        )))
  }

  /// The response type a request was inferred with, read from its generic parameter.
  static func responseType<Response>(of _: DigitalObjectRequest<Response>) -> Response.Type {
    Response.self
  }

  @Test("A download endpoint uses the reference's transport path")
  func aDownloadEndpointUsesTheReferencesTransportPath() throws {
    let reference = try Self.fdrPage()
    let endpoint = Endpoint.download(reference)
    #expect(Endpoint<DigitalObjectReceipt>.origin == "https://catalog.archives.gov")
    #expect(
      endpoint.path == "/medialz/presidential-libraries/roosevelt/577534/msf00611_Page_01.jpg")
    #expect(
      endpoint.url.absoluteString
        == "https://catalog.archives.gov/medialz/presidential-libraries/roosevelt/577534/msf00611_Page_01.jpg"
    )
    #expect(endpoint.reference?.naID == "122178160")
    #expect(endpoint.reference?.objectID == "122178162")
    #expect(
      endpoint.reference?.url
        == "https://s3.amazonaws.com/NARAprodstorage/lz/presidential-libraries/roosevelt/577534/msf00611_Page_01.jpg"
    )

    let live = Endpoint.download(
      try DigitalObjectReference(naID: "63545805", objectID: "63545806", url: Self.rg11LiveURL))
    #expect(
      live.path == "/medialive/5/5458/63545805/content/TB149/M1518/M1518_0007/images/0065.jpg")
  }

  @Test("A Catalog origin link forms an endpoint without a reference")
  func aCatalogOriginLinkFormsAnEndpointWithoutAReference() throws {
    let cases = [
      "https://catalog.archives.gov/medialz/presidential-libraries/roosevelt/577534/msf00611_Page_01.jpg",
      "https://catalog.archives.gov/medialive/5/5458/63545805/content/TB149/M1518/M1518_0007/images/0065.jpg",
      "https://catalog.archives.gov/medialz/a%20b/c.jpg",
    ]
    for link in cases {
      let url = try #require(URL(string: link))
      let endpoint = try #require(Endpoint<DigitalObjectReceipt>(link: url))
      #expect(Endpoint<DigitalObjectReceipt>.origin + endpoint.path == link)
      #expect(endpoint.url.absoluteString == link)
      #expect(endpoint.reference == nil)
    }
    let link = try #require(
      URL(
        string:
          "https://catalog.archives.gov/medialz/presidential-libraries/roosevelt/577534/msf00611_Page_01.jpg"
      ))
    let linked = try #require(Endpoint<DigitalObjectReceipt>(link: link))
    let downloaded = Endpoint.download(try Self.fdrPage())
    #expect(linked.path == downloaded.path)
    #expect(linked != downloaded)
  }

  @Test("Links outside the Catalog object policy are refused")
  func linksOutsideTheCatalogObjectPolicyAreRefused() throws {
    let cases = [
      Self.fdrPageURL,
      "http://catalog.archives.gov/medialz/a.jpg",
      "https://CATALOG.archives.gov/medialz/a.jpg",
      "https://catalog.archives.gov.example.com/medialz/a.jpg",
      "https://example.com/medialz/a.jpg",
      "https://user@catalog.archives.gov/medialz/a.jpg",
      "https://user:secret@catalog.archives.gov/medialz/a.jpg",
      "https://catalog.archives.gov:443/medialz/a.jpg",
      "https://catalog.archives.gov/medialz/a.jpg?versionId=1",
      "https://catalog.archives.gov/medialz/a.jpg#page",
      "https://catalog.archives.gov/medialz/",
      "https://catalog.archives.gov/medialz/../a.jpg",
      "https://catalog.archives.gov/medialz/a%2Fb.jpg",
      "https://catalog.archives.gov/medialz//a.jpg",
      "https://catalog.archives.gov/search?q=roosevelt",
      "https://catalog.archives.gov/id/122178160",
    ]
    for link in cases {
      let url = try #require(URL(string: link), "\(link)")
      #expect(Endpoint<DigitalObjectReceipt>(link: url) == nil, "\(link)")
    }
  }

  @Test("Download requests are inspectable values in every call form")
  func downloadRequestsAreInspectableValuesInEveryCallForm() throws {
    let reference = try Self.fdrPage()
    let stored = DigitalObjectRequest.download(reference)
    let annotated: DigitalObjectRequest<DigitalObjectReceipt> = stored
    let contextual: DigitalObjectRequest<DigitalObjectReceipt> = .download(reference)
    let named = try DigitalObjectRequest.rooseveltSpeechPage()
    #expect(stored.resolution == .endpoint(.download(reference)))
    #expect(annotated == contextual && contextual == named)
    #expect(Self.responseType(of: stored) == DigitalObjectReceipt.self)
    let endpoint: Endpoint<DigitalObjectReceipt> = .download(reference)
    #expect(DigitalObjectRequest(endpoint: endpoint) == stored)
    let other = DigitalObjectRequest.download(
      try DigitalObjectReference(naID: "63545805", objectID: "63545806", url: Self.rg11LiveURL))
    #expect(other != stored)
  }

  @Test("A consumer-defined response uses one link endpoint")
  func aConsumerDefinedResponseUsesOneLinkEndpoint() throws {
    let link = try #require(
      URL(
        string:
          "https://catalog.archives.gov/medialive/5/5458/63545805/content/TB149/M1518/M1518_0007/images/0065.jpg"
      ))
    let endpoint = try #require(Endpoint<ObjectHeaders>(link: link))
    let request = DigitalObjectRequest(endpoint: endpoint)
    #expect(request.resolution == .endpoint(endpoint))
    #expect(Self.responseType(of: request) == ObjectHeaders.self)
    #expect(
      endpoint.path == "/medialive/5/5458/63545805/content/TB149/M1518/M1518_0007/images/0065.jpg")
    #expect(endpoint.reference == nil)
  }

  @Test("The recorded image content type is the media type")
  func theRecordedImageContentTypeIsTheMediaType() throws {
    let receipt = try Self.receipt(
      headers: [
        .init(name: "Content-Type", value: "image/jpeg"),
        .init(name: "Content-Length", value: "65981"),
        .init(name: "X-Cache", value: "Hit from cloudfront"),
      ],
      reference: try Self.fdrPage())
    #expect(receipt.mediaType == "image/jpeg")
  }

  @Test("A response without a content type has no media type")
  func aResponseWithoutAContentTypeHasNoMediaType() throws {
    let recorded = try JSONDecoder().decode(
      [String: String].self, from: try Fixture.medialiveNoContentType.data())
    // The recorded headers are an unordered JSON object, so they are sorted here only to make
    // the receipt deterministic; the media type does not depend on order.
    let headers = recorded.sorted { $0.key < $1.key }.map {
      DigitalObjectReceipt.Header(name: $0.key, value: $0.value)
    }
    #expect(headers.count == 13)
    let receipt = try Self.receipt(headers: headers, reference: nil)
    #expect(receipt.mediaType == nil)
    #expect(try Self.receipt(headers: [], reference: nil).mediaType == nil)
  }

  @Test("A content type keeps its parameters and matches any name case")
  func aContentTypeKeepsItsParametersAndMatchesAnyNameCase() throws {
    // Synthetic headers: no recorded object response carries these spellings.
    let parameterized = try Self.receipt(
      headers: [.init(name: "Content-Type", value: "text/html; charset=utf-8")], reference: nil)
    #expect(parameterized.mediaType == "text/html; charset=utf-8")
    let mixedCase = try Self.receipt(
      headers: [
        .init(name: "X-Cache", value: "Hit from cloudfront"),
        .init(name: "cOnTeNt-TyPe", value: "TEXT/HTML; Charset=UTF-8"),
      ],
      reference: nil)
    #expect(mixedCase.mediaType == "TEXT/HTML; Charset=UTF-8")
    let duplicated = try Self.receipt(
      headers: [
        .init(name: "content-type", value: "image/jpeg"),
        .init(name: "Content-Type", value: "binary/octet-stream"),
      ],
      reference: nil)
    #expect(duplicated.mediaType == "image/jpeg")
  }

  @Test("A receipt keeps its evidence through encoding")
  func aReceiptKeepsItsEvidenceThroughEncoding() throws {
    let headers: [DigitalObjectReceipt.Header] = [
      .init(name: "Content-Type", value: "image/jpeg"),
      .init(name: "Via", value: "first"),
      .init(name: "Via", value: "second"),
    ]
    let receipt = try Self.receipt(headers: headers, reference: try Self.fdrPage())
    #expect(receipt.byteCount == 65_981)
    #expect(receipt.fileURL == URL(filePath: "/tmp/msf00611_Page_01.jpg"))
    #expect(receipt.headers == headers)
    #expect(receipt.reference?.naID == "122178160")
    #expect(receipt.retrievedAt.timeIntervalSince1970 == 1_790_517_142)
    #expect(receipt.status == 200)
    #expect(
      receipt.transportURL.absoluteString
        == "https://catalog.archives.gov/medialz/presidential-libraries/roosevelt/577534/msf00611_Page_01.jpg"
    )
    let decoded = try JSONDecoder().decode(
      DigitalObjectReceipt.self, from: try JSONEncoder().encode(receipt))
    #expect(decoded == receipt)
    #expect(decoded.headers.map(\.value) == ["image/jpeg", "first", "second"])

    let linked = try Self.receipt(headers: [], reference: nil)
    let object = try #require(
      try JSONSerialization.jsonObject(with: try JSONEncoder().encode(linked)) as? [String: Any])
    #expect(object["reference"] == nil)
    #expect(object["mediaType"] == nil)
    #expect(
      try JSONDecoder().decode(DigitalObjectReceipt.self, from: try JSONEncoder().encode(linked))
        == linked)
  }
}

/// A consumer-defined response type with no conformance requirement.
private struct ObjectHeaders {}

extension DigitalObjectRequest where Response == DigitalObjectReceipt {
  fileprivate static func rooseveltSpeechPage() throws -> Self {
    .download(
      try DigitalObjectReference(
        naID: "122178160", objectID: "122178162", url: RequestTests.fdrPageURL))
  }
}
