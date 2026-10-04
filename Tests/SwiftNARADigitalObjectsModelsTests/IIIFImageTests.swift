import Foundation
import SwiftNARADigitalObjectsModels
import SwiftNARADigitalObjectsTestSupport
import Testing

@Suite(.timeLimit(.minutes(suiteTimeLimitMinutes)))
struct IIIFImageTests {
  @Test("JPEG factories preserve literal syntax and independently inspectable values")
  func factories() throws {
    let information = try information()
    let forms: [(IIIFImageSize, String)] = [
      (try .fit(height: 200, width: 200), "!200,200"),
      (try .height(200), ",200"),
      (.maximum, "max"),
      (try .width(200), "200,"),
    ]
    for (size, parameter) in forms {
      let image = try IIIFImageRequest(information: information, size: size)
      let endpoint = Endpoint.image(image)
      let request = DigitalObjectRequest.image(image)
      #expect(
        image.path
          == "/iiif/3/lz%2Fpresidential-libraries%2Froosevelt%2F577534%2Fmsf00611_Page_01.jpg/full/"
          + parameter + "/0/default.jpg")
      #expect(image.information == information)
      #expect(endpoint.url == image.url)
      #expect(endpoint.imageRequest == image)
      #expect(request.resolution == .endpoint(endpoint))
      #expect(Endpoint<IIIFImageReceipt>(link: image.url) == nil)
    }
    #expect(throws: IIIFImageError.invalidSize) { try IIIFImageSize.width(0) }
    #expect(throws: IIIFImageError.invalidSize) { try IIIFImageSize.height(-1) }
    #expect(throws: IIIFImageError.invalidSize) { try IIIFImageSize.fit(height: 1, width: Int.min) }
  }

  @Test("Dimensions and advertised limits refuse oversized requests without clamping")
  func limits() throws {
    let original = try information()
    _ = try IIIFImageRequest(information: original, size: .width(1184))
    #expect(throws: IIIFImageError.invalidSize) {
      try IIIFImageRequest(information: original, size: .width(1185))
    }
    #expect(throws: IIIFImageError.invalidSize) {
      try IIIFImageRequest(information: original, size: .height(1499))
    }
    #expect(throws: IIIFImageError.invalidSize) {
      try IIIFImageRequest(information: original, size: .fit(height: 1500, width: 200))
    }
    let widthOnly = try information(["maxWidth": 200])
    #expect(widthOnly.maxHeight == nil)
    #expect(throws: IIIFImageError.limitExceeded) {
      try IIIFImageRequest(information: widthOnly, size: .width(200))
    }
    _ = try IIIFImageRequest(information: widthOnly, size: .height(200))
    let area = try information(["maxArea": 100])
    #expect(throws: IIIFImageError.limitExceeded) {
      try IIIFImageRequest(information: area, size: .fit(height: 200, width: 200))
    }
    #expect(
      try IIIFImageRequest(information: area, size: .maximum).path.hasSuffix(
        "/full/max/0/default.jpg"))
    let noLimits = try information(["maxArea": NSNull()])
    _ = try IIIFImageRequest(information: noLimits, size: .width(1184))
    let huge = try information(["height": Int.max, "width": Int.max, "maxArea": NSNull()])
    #expect(throws: IIIFImageError.limitExceeded) {
      try IIIFImageRequest(information: huge, size: .width(Int.max))
    }
    _ = try IIIFImageRequest(information: huge, size: .width(1))
  }

  @Test("Observed medialive maximum respects server area independently of original dimensions")
  func medialiveMaximum() throws {
    let source = try DigitalObjectReference(
      naID: "63545805", objectID: "63545806",
      url:
        "https://catalog.archives.gov/medialive/5/5458/63545805/content/TB149/M1518/M1518_0007/images/0065.jpg"
    )
    let information = try IIIFImageInformation.decode(
      Fixture.iiifMedialiveInformation.data(), reference: IIIFImageReference(reference: source))
    let request = try IIIFImageRequest(information: information, size: .maximum)
    #expect(
      request.path
        == "/iiif/3/opastorage%2Flive%2F5%2F5458%2F63545805%2Fcontent%2FTB149%2FM1518%2FM1518_0007%2Fimages%2F0065.jpg/full/max/0/default.jpg"
    )
    #expect(
      information.width == 2704 && information.height == 3775 && information.maxArea == 10_000_000)
    #expect(throws: IIIFImageError.limitExceeded) {
      try IIIFImageRequest(information: information, size: .width(2704))
    }
  }

  @Test("Profile and feature support are required without dereferencing external documents")
  func profiles() throws {
    let zero = try information(["profile": "level0", "extraFeatures": []])
    _ = try IIIFImageRequest(information: zero, size: .maximum)
    for size in [try IIIFImageSize.width(200), try .height(200), try .fit(height: 200, width: 200)]
    {
      #expect(throws: IIIFImageError.unsupportedFeature) {
        try IIIFImageRequest(information: zero, size: size)
      }
    }
    let one = try information(["profile": "level1", "extraFeatures": []])
    _ = try IIIFImageRequest(information: one, size: .width(200))
    _ = try IIIFImageRequest(information: one, size: .height(200))
    #expect(throws: IIIFImageError.unsupportedFeature) {
      try IIIFImageRequest(information: one, size: .fit(height: 200, width: 200))
    }
    let extra = try information(["profile": "level0", "extraFeatures": ["sizeByConfinedWh"]])
    _ = try IIIFImageRequest(information: extra, size: .fit(height: 200, width: 200))
    let unknown = try information(["profile": "future", "extraFeatures": ["sizeByW"]])
    #expect(throws: IIIFImageError.unsupportedFeature) {
      try IIIFImageRequest(information: unknown, size: .width(200))
    }
  }

  // Explicit synthetic information mutations; the attributed fixture remains unchanged.
  private func information(_ changes: [String: Any] = [:]) throws -> IIIFImageInformation {
    let source = try DigitalObjectReference(
      naID: "122178160", objectID: "122178162",
      url:
        "https://catalog.archives.gov/medialz/presidential-libraries/roosevelt/577534/msf00611_Page_01.jpg"
    )
    var object = try #require(
      JSONSerialization.jsonObject(with: Fixture.iiifFDRInformation.data()) as? [String: Any])
    for (key, value) in changes { object[key] = value }
    return try .decode(
      JSONSerialization.data(withJSONObject: object),
      reference: IIIFImageReference(reference: source))
  }
}
