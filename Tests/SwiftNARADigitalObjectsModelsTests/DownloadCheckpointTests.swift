import Foundation
import SwiftNARADigitalObjectsModels
import SwiftNARADigitalObjectsTestSupport
import Testing

@Suite(.timeLimit(.minutes(suiteTimeLimitMinutes)))
struct DownloadCheckpointTests {
  @Test("Decoding retains source identity and validates the versioned local binding")
  func decoding() throws {
    let value = try JSONDecoder().decode(DigitalObjectDownloadCheckpoint.self, from: bytes())
    #expect(value.committedByteCount == 0)
    #expect(value.contentEncoding == "identity")
    #expect(value.formatVersion == 1)
    #expect(value.reference.entityTag == "\"tag\"")
    #expect(value.reference.totalByteCount == 12)
    #expect(value.partialFileURL.path.hasSuffix("/partial"))
    #expect(value.checkpointURL.lastPathComponent == "checkpoint.json")
    #expect(
      try JSONDecoder().decode(
        DigitalObjectDownloadCheckpoint.self, from: JSONEncoder().encode(value)) == value)
  }

  @Test("Malformed state never bypasses offset digest path or source validation")
  func invalidState() throws {
    let changes: [(String, String)] = [
      ("\"committedByteCount\":0", "\"committedByteCount\":-1"),
      ("\"committedByteCount\":0", "\"committedByteCount\":13"),
      ("\"committedByteCount\":0", "\"committedByteCount\":1"),
      ("\"contentEncoding\":\"identity\"", "\"contentEncoding\":\"gzip\""),
      ("\"formatVersion\":1", "\"formatVersion\":2"),
      ("/partial", "/someone-elses-file"),
      ("file:///", "file://remote/"),
      ("file:///", "https://host/"),
      ("/private/tmp/", "/private/tmp/../tmp/"),
      ("e3b0c442", "00000000"),
      ("\"totalByteCount\":12", "\"totalByteCount\":0"),
      ("tag", "bad tag"),
    ]
    for (old, new) in changes {
      let changed = String(decoding: bytes(), as: UTF8.self).replacingOccurrences(
        of: old, with: new)
      #expect(throws: (any Error).self) {
        try JSONDecoder().decode(DigitalObjectDownloadCheckpoint.self, from: Data(changed.utf8))
      }
    }
  }

  private func bytes() -> Data {
    Data(
      #"""
      {
        "committedByteCount":0,
        "contentEncoding":"identity",
        "deviceID":1,
        "formatVersion":1,
        "id":"AD05A072-7D35-4AD0-826E-3C0E6472B1AD",
        "inode":2,
        "lastResponseHeaders":[],
        "partialFileURL":"file:///private/tmp/.nara-download-AD05A072-7D35-4AD0-826E-3C0E6472B1AD/partial",
        "prefixSHA256":"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
        "reference":{"entityTag":"\"tag\"", "object":{"naID":"1","objectID":"2","url":"https://catalog.archives.gov/medialz/example.jpg"}, "totalByteCount":12}
      }
      """#.utf8)
  }
}
