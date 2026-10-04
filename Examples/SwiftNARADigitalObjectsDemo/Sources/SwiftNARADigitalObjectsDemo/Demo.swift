import Foundation
import HTTPTesting
import SwiftNARADigitalObjects
import SwiftNARADigitalObjectsModels

@main
struct Demo {
  static func main() async throws {
    guard CommandLine.arguments.count == 2 else {
      print("Usage: SwiftNARADigitalObjectsDemo PATH_TO_RECORDED_FIXTURES")
      return
    }
    let fixtures = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
    let bytes = try Data(contentsOf: fixtures.appendingPathComponent("msf00611_Page_01.jpg"))
    let informationBytes = try Data(
      contentsOf: fixtures.appendingPathComponent("iiif-fdr-info.json"))
    let derivativeBytes = try Data(
      contentsOf: fixtures.appendingPathComponent("iiif-fdr-width200.jpg"))
    let transport = MockTransport(answers: [
      .success(
        .init(
          chunks: [bytes], headers: [.contentLength: "65981", .contentType: "image/jpeg"])),
      .success(
        .init(
          chunks: [informationBytes],
          headers: [.contentLength: "832", .contentType: "application/json"])),
      .success(
        .init(
          chunks: [derivativeBytes], headers: [.contentLength: "6031", .contentType: "image/jpeg"])),
    ])
    let client = DigitalObjectsClient(
      configuration: try DigitalObjectsConfiguration(
        maximumErrorBodyBytes: 4096, maximumObjectBytes: 100_000,
        userAgent: "(swift-nara demo, https://github.com/KalebCooper/swift-nara)"),
      retrievalTime: { Date(timeIntervalSince1970: 1_790_208_000) }, transport: transport)
    let reference = try DigitalObjectReference(
      naID: "122178160", objectID: "122178162",
      url:
        "https://s3.amazonaws.com/NARAprodstorage/lz/presidential-libraries/roosevelt/577534/msf00611_Page_01.jpg"
    )
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      "nara-media-demo-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: directory) }
    let receipt = try await client.download(
      reference, to: directory.appendingPathComponent("image.jpg"))
    print(
      "Saved \(receipt.byteCount) original bytes; media type \(receipt.mediaType ?? "undeclared").")
    print("Source: \(reference.url)")
    print("Transport: \(receipt.transportURL)")
    let information = try await client.imageInformation(
      for: IIIFImageReference(reference: reference))
    print(
      "IIIF information: \(information.width)x\(information.height), \(information.rawBytes.count) original JSON bytes."
    )
    let resize = try IIIFImageRequest(information: information, size: .width(200))
    let derivative = try await client.downloadImage(
      resize, to: directory.appendingPathComponent("width200.jpg"))
    print(
      "Saved \(derivative.byteCount) derivative bytes for \(derivative.request.size.parameter).")
    print("Replayed \(transport.requests.count) recorded responses; no live request.")
  }
}
