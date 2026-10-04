import Crypto
import Foundation

/// Hashes committed local bytes with bounded memory; ETags are never interpreted as digests.
struct DigitalObjectDownloadFile {
  static func digest(handle: FileHandle, length: Int64) throws -> String {
    try hash(handle: handle, length: length).finalize().map {
      ($0 < 16 ? "0" : "") + String($0, radix: 16)
    }.joined()
  }

  static func hash(handle: FileHandle, length: Int64) throws -> SHA256 {
    try Task.checkCancellation()
    guard length >= 0 else { throw CocoaError(.fileReadCorruptFile) }
    try handle.seek(toOffset: 0)
    var remaining = length
    var hash = SHA256()
    while remaining > 0 {
      try Task.checkCancellation()
      let bytes = try handle.read(upToCount: Int(min(remaining, 65_536))) ?? Data()
      guard !bytes.isEmpty else { throw CocoaError(.fileReadCorruptFile) }
      hash.update(data: bytes)
      remaining -= Int64(bytes.count)
    }
    return hash
  }
}
