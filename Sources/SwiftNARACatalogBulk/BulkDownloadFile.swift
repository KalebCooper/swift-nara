import Crypto
import Foundation
import SwiftNARACatalogBulkModels
import SystemPackage
#if canImport(Darwin)
import Darwin
#elseif canImport(Android)
import Android
#else
import Glibc
#endif

/// Owns one locked descriptor for the duration of a local download operation.
struct BulkDownloadFile {
  let descriptor: FileDescriptor
  let directoryDescriptor: FileDescriptor
  let directoryIdentity: Stat
  let handle: FileHandle
  let url: URL

  init(checkpoint: BulkDownloadCheckpoint, forDiscard: Bool = false) throws {
    let directory = checkpoint.partialFileURL.deletingLastPathComponent()
    guard directory.resolvingSymlinksInPath() == directory else {
      throw BulkDownloadStateError.fileChanged
    }
    let directoryDescriptor = try FileDescriptor.open(
      FilePath(directory.path), .readOnly, options: [.closeOnExec, .directory, .noFollow])
    do {
      let directoryIdentity = try Stat(directoryDescriptor)
      guard directoryIdentity.type == .directory,
        directoryIdentity.permissions.rawValue & 0o077 == 0,
        directoryIdentity.userID.rawValue == geteuid()
      else { throw BulkDownloadStateError.invalidWorkspace }
      let descriptor = try FileDescriptor.open(
        FilePath(checkpoint.partialFileURL.path), .readWrite,
        options: [.closeOnExec, .noFollow, .nonBlocking])
      do {
        guard flock(descriptor.rawValue, LOCK_EX | LOCK_NB) == 0 else {
          throw BulkDownloadStateError.writerConflict
        }
        self.descriptor = descriptor
        self.directoryDescriptor = directoryDescriptor
        self.directoryIdentity = directoryIdentity
        self.handle = FileHandle(fileDescriptor: descriptor.rawValue, closeOnDealloc: false)
        self.url = checkpoint.partialFileURL
        try verify(checkpoint, allowLinks: forDiscard)
      } catch {
        try? descriptor.close()
        throw error
      }
    } catch {
      try? directoryDescriptor.close()
      throw error
    }
  }

  func close() {
    try? handle.close()
    try? directoryDescriptor.close()
  }

  static func digest(handle: FileHandle, length: Int64) throws -> String {
    hexadecimal(try hash(handle: handle, length: length))
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

  static func hexadecimal(_ hash: SHA256) -> String {
    hash.finalize().map { ($0 < 16 ? "0" : "") + String($0, radix: 16) }.joined()
  }

  static func persist(_ checkpoint: BulkDownloadCheckpoint) throws {
    let bytes = try JSONEncoder().encode(checkpoint)
    guard bytes.count <= 1_048_576 else { throw BulkDownloadStateError.invalidCheckpoint }
    try bytes.write(to: checkpoint.checkpointURL, options: .atomic)
    let descriptor = try FileDescriptor.open(
      FilePath(checkpoint.checkpointURL.path), .readOnly, options: [.closeOnExec, .noFollow])
    defer { try? descriptor.close() }
    guard fsync(descriptor.rawValue) == 0 else { throw Errno(rawValue: errno) }
    let directory = try FileDescriptor.open(
      FilePath(checkpoint.partialFileURL.deletingLastPathComponent().path), .readOnly,
      options: [.closeOnExec, .directory, .noFollow])
    defer { try? directory.close() }
    guard fsync(directory.rawValue) == 0 else { throw Errno(rawValue: errno) }
  }

  func readCheckpoint(matching supplied: BulkDownloadCheckpoint) throws -> BulkDownloadCheckpoint {
    let descriptor = try FileDescriptor.open(
      FilePath(supplied.checkpointURL.path), .readOnly,
      options: [.closeOnExec, .noFollow, .nonBlocking])
    let input = FileHandle(fileDescriptor: descriptor.rawValue, closeOnDealloc: false)
    defer { try? input.close() }
    let metadata = try Stat(descriptor)
    guard metadata.type == .regular, metadata.linkCount == 1,
      metadata.size > 0, metadata.size <= 1_048_576
    else { throw BulkDownloadStateError.invalidCheckpoint }
    let bytes = try input.read(upToCount: 1_048_577) ?? Data()
    guard bytes.count <= 1_048_576 else { throw BulkDownloadStateError.invalidCheckpoint }
    let stored: BulkDownloadCheckpoint
    do { stored = try JSONDecoder().decode(BulkDownloadCheckpoint.self, from: bytes) } catch {
      throw BulkDownloadStateError.invalidCheckpoint
    }
    guard stored.deviceID == supplied.deviceID, stored.id == supplied.id,
      stored.inode == supplied.inode, stored.partialFileURL == supplied.partialFileURL,
      stored.reference == supplied.reference,
      stored.committedByteCount >= supplied.committedByteCount
    else { throw BulkDownloadStateError.invalidCheckpoint }
    return stored
  }

  func rollback(matching checkpoint: BulkDownloadCheckpoint) throws {
    let stored = try readCheckpoint(matching: checkpoint)
    try verify(stored)
    guard try Stat(descriptor).size >= stored.committedByteCount else {
      throw BulkDownloadStateError.invalidCheckpoint
    }
    try handle.truncate(atOffset: UInt64(stored.committedByteCount))
    try handle.synchronize()
  }

  static func synchronize(_ descriptor: FileDescriptor) throws {
    guard fsync(descriptor.rawValue) == 0 else { throw Errno(rawValue: errno) }
  }

  func verify(_ checkpoint: BulkDownloadCheckpoint, allowLinks: Bool = false) throws {
    let directory = url.deletingLastPathComponent()
    guard directory.resolvingSymlinksInPath() == directory else {
      throw BulkDownloadStateError.fileChanged
    }
    let currentDirectory = try Stat(FilePath(directory.path), followTargetSymlink: false)
    let metadata = try Stat(descriptor)
    let pathMetadata = try Stat(FilePath(url.path), followTargetSymlink: false)
    guard currentDirectory.type == .directory,
      currentDirectory.deviceID == directoryIdentity.deviceID,
      currentDirectory.inode == directoryIdentity.inode,
      metadata.type == .regular, pathMetadata.type == .regular,
      allowLinks || metadata.linkCount == 1,
      metadata.deviceID == pathMetadata.deviceID, metadata.inode == pathMetadata.inode,
      UInt64(truncatingIfNeeded: metadata.deviceID.rawValue) == checkpoint.deviceID,
      UInt64(truncatingIfNeeded: metadata.inode.rawValue) == checkpoint.inode
    else { throw BulkDownloadStateError.fileChanged }
  }
}
