import Foundation

/// Official digital object captures; exact requests, instants, headers, sizes, and hashes are in
/// attribution.json.
package enum Fixture: String, CaseIterable {
  /// Capture attribution including exact range requests.
  case attribution = "attribution.json"
  /// Response headers of the 200 image/tiff with X-Cache "Miss from cloudfront" to a HEAD of
  /// /medialz/dc-metro/rg-011/299798/RIT_March_2020/162246501/162246501-004_ma.tif on
  /// catalog.archives.gov, with no query, on September 28, 2026 UTC; the response had no body.
  case cacheMissObject = "cache-miss-object.headers.json"
  /// Response headers of the 200 text/html to a HEAD of
  /// /medialive/28/8797/26879728/content/electronic-records/rg-267/appellate/96-289.HTM on
  /// catalog.archives.gov, with no query, on September 28, 2026 UTC; an archival HTML object.
  case htmlObjectMedialive = "html-object-medialive.headers.json"
  /// Response headers of the 200 text/html to a HEAD of
  /// /medialz/electronic-records/rg-341/ALOREPMACAL/AL1.6809.ARLAY.html on catalog.archives.gov,
  /// with no query, on September 28, 2026 UTC; an archival HTML object.
  case htmlObjectMedialz = "html-object-medialz.headers.json"
  /// Unchanged IIIF information for the reviewed FDR JPEG.
  case iiifFDRInformation = "iiif-fdr-info.json"
  /// Unchanged 200-pixel-wide JPEG derivative of the reviewed FDR object.
  case iiifFDRWidth200 = "iiif-fdr-width200.jpg"
  /// Unchanged IIIF service metadata for the medialive object; no media bytes.
  case iiifMedialiveInformation = "iiif-medialive-info.json"
  /// Response headers of the 200 to a HEAD of
  /// /medialive/5/5458/63545805/content/TB149/M1518/M1518_0007/images/0065.jpg on
  /// catalog.archives.gov, with no query; the response had no body and no Content-Type.
  case medialiveNoContentType = "medialive-no-content-type.headers.json"
  /// Body of the 200 text/html to a GET of
  /// /medialive/5/5458/63545805/content/TB149/M1518/M1518_0007/images/swift-nara-nonexistent-object.jpg
  /// on catalog.archives.gov, with no query, on September 28, 2026 UTC, a key chosen not to exist;
  /// unchanged.
  case missingMedialiveObject = "missing-medialive-object.html"
  /// Body of the 200 text/html to a GET of
  /// /medialz/presidential-libraries/roosevelt/577534/swift-nara-nonexistent-object.jpg on
  /// catalog.archives.gov, with no query, a key chosen not to exist; unchanged.
  case missingObject = "missing-object.html"
  /// Body of the 200 image/jpeg to a GET of
  /// /medialz/presidential-libraries/roosevelt/577534/msf00611_Page_01.jpg on
  /// catalog.archives.gov, with no query; unchanged.
  case msf00611Page01 = "msf00611_Page_01.jpg"

  /// Bytes 16 through 47 of the reviewed FDR JPEG, never a complete image.
  case rangeFDRJPEG = "range-fdr-jpeg.bin"
  /// Bytes 16 through 47 of the reviewed archival HTML object, never a complete document.
  case rangeMedialiveHTML = "range-medialive-html.bin"

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
