import Foundation
import SwiftNARADigitalObjectsModels
import SwiftNARADigitalObjectsTestSupport
import Testing

@Suite(.timeLimit(.minutes(suiteTimeLimitMinutes)))
struct IIIFInformationTests {
  @Test("Both captured services retain dimensions limits tiles and exact bytes")
  func captures() throws {
    let fdr = try IIIFImageInformation.decode(
      Fixture.iiifFDRInformation.data(), reference: reference())
    #expect(fdr.width == 1184 && fdr.height == 1498)
    #expect(fdr.maxArea == 1_773_632)
    #expect(fdr.maxWidth == nil && fdr.maxHeight == nil)
    #expect(fdr.profile == "level2")
    #expect(fdr.sizes?.map(\.width) == [74, 148, 296, 592, 1184])
    #expect(fdr.tiles?.first?.scaleFactors == [1, 2, 4, 8, 16])
    #expect(fdr.extraFeatures?.contains("sizeByConfinedWh") == true)
    #expect(try fdr.rawBytes == Fixture.iiifFDRInformation.data())
    #expect(fdr.status == nil && fdr.retrievedAt == nil && fdr.headers.isEmpty)
    let live = IIIFImageReference(
      reference: try DigitalObjectReference(
        naID: "63545805", objectID: "63545806",
        url:
          "https://catalog.archives.gov/medialive/5/5458/63545805/content/TB149/M1518/M1518_0007/images/0065.jpg"
      ))
    let information = try IIIFImageInformation.decode(
      Fixture.iiifMedialiveInformation.data(), reference: live)
    #expect(information.width == 2704 && information.height == 3775)
    #expect(information.maxArea == 10_000_000)
    #expect(information.sizes?.count == 5)
    #expect(try information.rawBytes == Fixture.iiifMedialiveInformation.data())
  }

  @Test("Information refuses hostile identities invalid shapes and unsupported versions")
  func malformed() throws {
    let data = try Fixture.iiifFDRInformation.data()
    let original = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    let mutations: [(String, Any)] = [
      ("id", "https://example.org/iiif/3/other"),
      ("id", "https://user@catalog.archives.gov/iiif/3/other"),
      ("id", "https://catalog.archives.gov/iiif/3/other"),
      ("height", 0), ("width", -1), ("width", "1184"), ("maxArea", 0),
      ("maxHeight", 100), ("sizes", [["height": 1, "width": 0]]),
      ("tiles", [["width": 512, "scaleFactors": [0]]]),
      ("type", "ImageService2"), ("protocol", "https://example.org/protocol"),
    ]
    for (key, value) in mutations {
      var document = original
      document[key] = value
      let bytes = try JSONSerialization.data(withJSONObject: document)
      #expect(throws: IIIFImageError.self) {
        try IIIFImageInformation.decode(bytes, reference: reference())
      }
    }
    #expect(throws: IIIFImageError.limitExceeded) {
      try IIIFImageInformation.decode(data, maximumBytes: 1, reference: reference())
    }
    #expect(throws: IIIFImageError.malformedInformation) {
      try IIIFImageInformation.decode(Data("<html/>".utf8), reference: reference())
    }
  }

  @Test("Mapping encodes the source key once and factories preserve their operation")
  func mappingAndFactories() throws {
    let image = try reference()
    #expect(
      image.informationURL.absoluteString
        == "https://catalog.archives.gov/iiif/3/lz%2Fpresidential-libraries%2Froosevelt%2F577534%2Fmsf00611_Page_01.jpg/info.json"
    )
    let escaped = IIIFImageReference(
      reference: try DigitalObjectReference(
        naID: "1", objectID: nil, url: "https://catalog.archives.gov/medialz/a%20b/%252F.jpg"))
    #expect(escaped.servicePath == "/iiif/3/lz%2Fa%20b%2F%252F.jpg")
    let request = DigitalObjectRequest.imageInformation(image)
    let endpoint = Endpoint.imageInformation(image)
    #expect(request.resolution == .endpoint(endpoint))
    #expect(endpoint.imageReference == image)
    #expect(endpoint.reference == nil)
    #expect(Endpoint<DigitalObjectReceipt>(link: image.informationURL) == nil)
    for path in ["a/%2F.jpg", "%2e%2e/a.jpg", "a/%ZZ.jpg", "a/%5c.jpg"] {
      #expect(throws: DigitalObjectReferenceError.self) {
        try DigitalObjectReference(
          naID: "1", objectID: nil, url: "https://catalog.archives.gov/medialz/" + path)
      }
    }
  }

  @Test("Unknown codes nulls absent limits and linked contexts remain raw without fetching")
  func unknownAndNull() throws {
    var document = try #require(
      JSONSerialization.jsonObject(with: Fixture.iiifFDRInformation.data()) as? [String: Any])
    document["extraFeatures"] = ["future-feature", "sizeByW"]
    document["maxArea"] = NSNull()
    document["profile"] = "future-profile"
    document["future"] = ["unknown": NSNull()]
    document["@context"] = [
      "http://iiif.io/api/image/3/context.json", "https://example.org/context",
    ]
    let bytes = try JSONSerialization.data(withJSONObject: document)
    let value = try IIIFImageInformation.decode(bytes, reference: reference())
    #expect(value.rawBytes == bytes)
    #expect(value.maxArea == nil)
    #expect(value.profile == "future-profile")
    #expect(value.extraFeatures == ["future-feature", "sizeByW"])
  }

  private func reference() throws -> IIIFImageReference {
    IIIFImageReference(
      reference: try DigitalObjectReference(
        naID: "122178160", objectID: "122178162",
        url:
          "https://catalog.archives.gov/medialz/presidential-libraries/roosevelt/577534/msf00611_Page_01.jpg"
      ))
  }
}
