import Foundation
import SwiftNARACatalogBulkModels

/// Lazy local JSONL records with bounded line buffering and exact source provenance.
///
/// Construction performs no I/O. Each iterator opens the file independently on its first read.
/// Blank or malformed lines are errors, not silently skipped. The final line may omit LF; CRLF
/// and LF bytes are preserved. A failure terminates that iterator. Keep the file immutable while
/// reading it; a byte-count check cannot detect every same-size edit.
/// ```swift
/// let lines = try CatalogLineSequence(shard: receipt)
/// for try await line in lines { print(line.lineNumber, line.record.naID) }
/// ```
public struct CatalogLineSequence: AsyncSequence, Sendable {
  /// One decoded line with its source bytes and location.
  public typealias Element = CatalogLine
  /// The service's typed reading failure.
  public typealias Failure = CatalogBulkError

  /// An exclusive file cursor, closing its descriptor on completion, failure, or release.
  public struct Iterator: AsyncIteratorProtocol {
    /// One decoded physical line.
    public typealias Element = CatalogLine
    /// The typed local reading failure.
    public typealias Failure = CatalogBulkError
    private var finished = false
    private let maximumLineBytes: Int
    private var reader: LocalShardReader?
    private let shard: ShardReceipt

    init(maximumLineBytes: Int, shard: ShardReceipt) {
      self.maximumLineBytes = maximumLineBytes; self.shard = shard
    }

    /// Reads only far enough to return one line.
    /// - Returns: The next line, or nil after completion or failure.
    /// - Throws: `CatalogBulkError.line` with the physical location, file errors, or cancellation.
    public mutating func next(isolation actor: isolated (any Actor)? = #isolation)
      async throws(CatalogBulkError) -> CatalogLine?
    {
      guard !finished else { return nil }
      finished = true
      do {
        guard !Task.isCancelled else { throw CatalogBulkError.cancelled }
        if reader == nil { reader = try LocalShardReader(shard: shard) }
        guard let reader else { return nil }
        guard let line = try reader.next(maximumLineBytes: maximumLineBytes, shard: shard) else {
          self.reader = nil; return nil
        }
        finished = false
        return line
      } catch let error as CatalogBulkError { reader = nil; throw error } catch {
        reader = nil; throw Task.isCancelled ? .cancelled : .file(error)
      }
    }
  }

  private let maximumLineBytes: Int
  private let shard: ShardReceipt

  /// Describes a local file traversal without opening it.
  /// - Parameters:
  ///   - maximumLineBytes: The bound including a line terminator, defaulting to 8 MiB.
  ///   - shard: The completed download or supplied-file receipt.
  /// - Throws: `CatalogBulkError.invalidConfiguration` for invalid bounds or a non-file URL.
  public init(maximumLineBytes: Int = 8 * 1024 * 1024, shard: ShardReceipt) throws(CatalogBulkError)
  {
    guard maximumLineBytes > 0, shard.byteCount >= 0, shard.fileURL.isFileURL else {
      throw .invalidConfiguration
    }
    self.maximumLineBytes = maximumLineBytes; self.shard = shard
  }

  /// Creates an independent iterator without opening the file.
  public func makeAsyncIterator() -> Iterator {
    Iterator(maximumLineBytes: maximumLineBytes, shard: shard)
  }
}

private final class LocalShardReader {
  private var buffer = Data()
  private var bufferIndex = 0
  private let handle: FileHandle
  private var lineNumber: Int64 = 0
  private var offset: Int64 = 0
  private var readBytes: Int64 = 0

  init(shard: ShardReceipt) throws {
    handle = try FileHandle(forReadingFrom: shard.fileURL)
    let size = try handle.seekToEnd()
    guard size == UInt64(shard.byteCount) else {
      try handle.close(); throw CatalogBulkError.sizeMismatch
    }
    try handle.seek(toOffset: 0)
  }

  deinit { try? handle.close() }

  func next(maximumLineBytes: Int, shard: ShardReceipt) throws -> CatalogLine? {
    var line = Data()
    while true {
      guard !Task.isCancelled else { throw CatalogBulkError.cancelled }
      if bufferIndex == buffer.count {
        buffer = try handle.read(upToCount: min(65536, maximumLineBytes)) ?? Data()
        bufferIndex = 0
        guard Int64(buffer.count) <= shard.byteCount - readBytes else {
          throw CatalogBulkError.sizeMismatch
        }
        readBytes += Int64(buffer.count)
        if buffer.isEmpty {
          guard readBytes == shard.byteCount else { throw CatalogBulkError.sizeMismatch }
          if line.isEmpty { return nil }
          break
        }
      }
      let remainder = buffer[bufferIndex...]
      let newline = remainder.firstIndex(of: 10)
      let end = newline.map { $0 + 1 } ?? buffer.count
      guard end - bufferIndex <= maximumLineBytes - line.count else {
        throw CatalogBulkError.line(
          byteOffset: offset, lineNumber: lineNumber + 1, reason: .limitExceeded)
      }
      line.append(contentsOf: buffer[bufferIndex..<end]); bufferIndex = end
      if newline != nil { break }
    }
    let record: CatalogRecord
    do { record = try CatalogRecord.decode(line, maximumBytes: maximumLineBytes) } catch {
      throw CatalogBulkError.line(byteOffset: offset, lineNumber: lineNumber + 1, reason: error)
    }
    guard !Task.isCancelled else { throw CatalogBulkError.cancelled }
    lineNumber += 1
    let result = CatalogLine(
      byteOffset: offset, lineNumber: lineNumber, rawBytes: line, record: record, shard: shard)
    offset += Int64(line.count)
    return result
  }
}
