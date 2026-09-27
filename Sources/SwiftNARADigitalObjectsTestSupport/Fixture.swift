import Foundation

/// Official digital object captures; exact requests, instants, headers, sizes, and hashes are in
/// attribution.json.
package enum Fixture: String, CaseIterable {
  /// Response headers of the 200 to a HEAD of
  /// /medialive/5/5458/63545805/content/TB149/M1518/M1518_0007/images/0065.jpg on
  /// catalog.archives.gov, with no query; the response had no body and no Content-Type.
  case medialiveNoContentType = "medialive-no-content-type.headers.json"
  /// Body of the 200 text/html to a GET of
  /// /medialz/presidential-libraries/roosevelt/577534/swift-nara-nonexistent-object.jpg on
  /// catalog.archives.gov, with no query, a key chosen not to exist; unchanged.
  case missingObject = "missing-object.html"
  /// Body of the 200 image/jpeg to a GET of
  /// /medialz/presidential-libraries/roosevelt/577534/msf00611_Page_01.jpg on
  /// catalog.archives.gov, with no query; unchanged.
  case msf00611Page01 = "msf00611_Page_01.jpg"

  /// Loads one recorded body without a live request.
  package func data() throws -> Data { try Data(contentsOf: url()) }

  /// Locates the original fixture for independent local reading.
  package func url() throws -> URL {
    guard
      let url = Bundle.module.url(
        forResource: rawValue, withExtension: nil, subdirectory: "Fixtures")
    else {
      throw CocoaError(.fileReadNoSuchFile)
    }
    return url
  }
}
