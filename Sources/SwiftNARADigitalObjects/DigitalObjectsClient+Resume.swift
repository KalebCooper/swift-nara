import Foundation
import SwiftNARADigitalObjectsModels
import SystemPackage

extension DigitalObjectsClient {
  /// Creates retained local download state without a network request.
  ///
  /// The caller supplies a known strong validator and total length, which is the explicit
  /// whole-download budget. Each future transfer is bounded by maximumRangeBytes.
  /// Keep the workspace private and stable, and do not mutate owned files during SDK operations.
  /// A failed initialization may leave a private child directory for caller inspection and cleanup.
  /// - Parameters:
  ///   - reference: The exact known original representation.
  ///   - workspace: An existing caller-owned directory.
  /// - Returns: A synchronized zero-byte checkpoint in a private child directory.
  /// - Throws: `DigitalObjectsError` for cancellation or local state/file failure.
  public func beginDownload(_ reference: DigitalObjectRangeReference, in workspace: URL)
    throws(DigitalObjectsError) -> DigitalObjectDownloadCheckpoint
  {
    do {
      try Task.checkCancellation()
      guard workspace.isFileURL, workspace.query == nil, workspace.fragment == nil,
        workspace.host == nil || workspace.host == "",
        workspace.user == nil, workspace.password == nil, workspace.port == nil
      else { throw DigitalObjectDownloadStateError.invalidWorkspace }
      let parent = workspace.standardizedFileURL.resolvingSymlinksInPath()
      let parentDescriptor = try FileDescriptor.open(
        FilePath(parent.path), .readOnly, options: [.closeOnExec, .directory, .noFollow])
      defer { try? parentDescriptor.close() }
      let id = UUID()
      let directory = parent.appendingPathComponent(".nara-download-" + id.uuidString)
      guard (try? FileManager.default.attributesOfItem(atPath: directory.path)) == nil else {
        throw DigitalObjectDownloadStateError.invalidWorkspace
      }
      try FileManager.default.createDirectory(
        at: directory, withIntermediateDirectories: false,
        attributes: [.posixPermissions: 0o700])
      let partial = directory.appendingPathComponent("partial")
      let descriptor = try FileDescriptor.open(
        FilePath(partial.path), .readWrite,
        options: [.closeOnExec, .create, .exclusiveCreate, .noFollow],
        permissions: [.ownerRead, .ownerWrite])
      let handle = FileHandle(fileDescriptor: descriptor.rawValue, closeOnDealloc: false)
      defer { try? handle.close() }
      let metadata = try Stat(descriptor)
      let checkpoint = try DigitalObjectDownloadCheckpoint(
        committedByteCount: 0,
        deviceID: UInt64(truncatingIfNeeded: metadata.deviceID.rawValue), id: id,
        inode: UInt64(truncatingIfNeeded: metadata.inode.rawValue),
        lastResponseHeaders: [], lastRetrievedAt: nil, partialFileURL: partial,
        prefixSHA256: DigitalObjectDownloadFile.hexadecimal(.init()), reference: reference)
      try handle.synchronize()
      try saveCheckpoint(checkpoint)
      try DigitalObjectDownloadFile.synchronize(parentDescriptor)
      return checkpoint
    } catch { throw Self.downloadError(error) }
  }

  /// Removes only the bound partial and sidecar, including after publication.
  ///
  /// The private child directory and any other files remain. Corrupt partial bytes may be
  /// discarded when file identity and the sidecar binding still match. Missing or replaced
  /// files are refused. Published hard links remain intact.
  /// - Parameter checkpoint: Any earlier checkpoint for the same owned download.
  /// - Throws: `DigitalObjectsError` for cancellation, changed ownership or local file failure.
  public func discardDownload(_ checkpoint: DigitalObjectDownloadCheckpoint)
    throws(DigitalObjectsError)
  {
    do {
      try Task.checkCancellation()
      let file = try DigitalObjectDownloadFile(checkpoint: checkpoint, forDiscard: true)
      defer { file.close() }
      let current = try file.readCheckpoint(matching: checkpoint)
      try file.verify(current, allowLinks: true)
      try FileManager.default.removeItem(at: current.partialFileURL)
      try FileManager.default.removeItem(at: current.checkpointURL)
      try DigitalObjectDownloadFile.synchronize(file.directoryDescriptor)
    } catch { throw Self.downloadError(error) }
  }

  /// Continues serial ranges from the verified durable prefix and publishes a complete new file.
  /// - Parameters:
  ///   - checkpoint: A prior checkpoint; a newer matching sidecar is loaded automatically.
  ///   - destination: A new file on the same filesystem; existing destinations are refused.
  /// - Returns: Complete bytes and the retained checkpoint. Call discardDownload to remove owned state.
  /// - Throws: `DigitalObjectDownloadFailure` with the last verified durable boundary; never retries.
  public func resumeDownload(_ checkpoint: DigitalObjectDownloadCheckpoint, to destination: URL)
    async throws(DigitalObjectDownloadFailure) -> DigitalObjectDownloadReceipt
  {
    try await value(
      for: .resumableDownload(checkpoint.reference), checkpoint: checkpoint, to: destination)
  }

  /// Executes a resumable endpoint with local state supplied separately.
  ///
  /// Interrupted writes are rolled back to the sidecar boundary when possible. A later resume
  /// verifies the digest before truncating any remaining uncommitted tail. Publication creates
  /// a new hard link and retains the owned partial and sidecar for explicit discard. Cancellation
  /// observed before publication preserves progress; publication is the completion boundary.
  /// If directory synchronization fails after linking, the complete destination may already exist.
  /// Keep both parent directories stable during execution. Advisory locks coordinate SDK writers;
  /// they do not prevent arbitrary external processes from modifying the same files.
  /// - Parameters:
  ///   - endpoint: A resumable-download factory endpoint for the checkpoint's exact reference.
  ///   - checkpoint: An earlier checkpoint for this download.
  ///   - destination: A new same-filesystem destination beneath an existing directory.
  /// - Returns: A complete-file receipt only after length, identity and digest checks.
  /// - Throws: `DigitalObjectDownloadFailure` for invalid state, HTTP, cancellation or file failure.
  public func send(
    _ endpoint: Endpoint<DigitalObjectDownloadReceipt>, checkpoint: DigitalObjectDownloadCheckpoint,
    to destination: URL
  ) async throws(DigitalObjectDownloadFailure) -> DigitalObjectDownloadReceipt {
    var current: DigitalObjectDownloadCheckpoint?
    var opened: DigitalObjectDownloadFile?
    defer { opened?.close() }
    do {
      try Task.checkCancellation()
      guard endpoint.downloadReference == checkpoint.reference,
        destination.isFileURL, destination.query == nil, destination.fragment == nil,
        destination.host == nil || destination.host == "",
        destination.user == nil, destination.password == nil, destination.port == nil,
        destination.standardizedFileURL == destination
      else { throw DigitalObjectsError.invalidConfiguration }
      if (try? FileManager.default.attributesOfItem(atPath: destination.path)) != nil {
        throw CocoaError(.fileWriteFileExists)
      }
      let file = try DigitalObjectDownloadFile(checkpoint: checkpoint)
      opened = file
      let stored = try file.readCheckpoint(matching: checkpoint)
      let destinationDirectory = try FileDescriptor.open(
        FilePath(destination.deletingLastPathComponent().resolvingSymlinksInPath().path),
        .readOnly, options: [.closeOnExec, .directory, .noFollow])
      defer { try? destinationDirectory.close() }
      guard try Stat(destinationDirectory).deviceID == Stat(file.descriptor).deviceID else {
        throw DigitalObjectsError.invalidConfiguration
      }
      var hash = try DigitalObjectDownloadFile.hash(
        handle: file.handle, length: stored.committedByteCount)
      guard DigitalObjectDownloadFile.hexadecimal(hash) == stored.prefixSHA256 else {
        throw DigitalObjectDownloadStateError.integrityMismatch
      }
      try file.verify(stored)
      try file.handle.truncate(atOffset: UInt64(stored.committedByteCount))
      try file.handle.synchronize()
      current = stored
      var progress = stored
      while progress.committedByteCount < progress.reference.totalByteCount {
        try Task.checkCancellation()
        let count = min(
          configuration.maximumRangeBytes,
          progress.reference.totalByteCount - progress.committedByteCount)
        let range = try DigitalObjectByteRange(
          lowerBound: progress.committedByteCount,
          upperBound: progress.committedByteCount + count - 1)
        let fragment = progress.partialFileURL.deletingLastPathComponent()
          .appendingPathComponent("range-" + UUID().uuidString)
        let rangeReceipt = try await downloadRange(range, of: progress.reference, to: fragment)
        defer { try? FileManager.default.removeItem(at: fragment) }
        try file.verify(progress)
        guard try file.readCheckpoint(matching: progress) == progress else {
          throw DigitalObjectDownloadStateError.invalidCheckpoint
        }
        let inputDescriptor = try FileDescriptor.open(
          FilePath(fragment.path), .readOnly, options: [.closeOnExec, .noFollow, .nonBlocking])
        let input = FileHandle(fileDescriptor: inputDescriptor.rawValue, closeOnDealloc: false)
        defer { try? input.close() }
        guard try Stat(inputDescriptor).type == .regular else {
          throw DigitalObjectDownloadStateError.fileChanged
        }
        try file.handle.seek(toOffset: UInt64(progress.committedByteCount))
        var remaining = count
        while remaining > 0 {
          try Task.checkCancellation()
          let bytes = try input.read(upToCount: Int(min(remaining, 65_536))) ?? Data()
          guard !bytes.isEmpty else { throw CocoaError(.fileReadCorruptFile) }
          try file.handle.write(contentsOf: bytes)
          hash.update(data: bytes)
          remaining -= Int64(bytes.count)
        }
        try file.handle.synchronize()
        let next = try DigitalObjectDownloadCheckpoint(
          committedByteCount: progress.committedByteCount + count,
          deviceID: progress.deviceID, id: progress.id, inode: progress.inode,
          lastResponseHeaders: rangeReceipt.headers, lastRetrievedAt: rangeReceipt.retrievedAt,
          partialFileURL: progress.partialFileURL,
          prefixSHA256: DigitalObjectDownloadFile.hexadecimal(hash), reference: progress.reference)
        try file.verify(progress)
        try saveCheckpoint(next)
        current = next
        progress = next
      }
      try file.verify(progress)
      guard try Stat(file.descriptor).size == progress.reference.totalByteCount,
        try DigitalObjectDownloadFile.digest(
          handle: file.handle, length: progress.committedByteCount)
          == progress.prefixSHA256
      else { throw DigitalObjectDownloadStateError.integrityMismatch }
      try Task.checkCancellation()
      try FileManager.default.linkItem(at: progress.partialFileURL, to: destination)
      try DigitalObjectDownloadFile.synchronize(destinationDirectory)
      return DigitalObjectDownloadReceipt(checkpoint: progress, fileURL: destination)
    } catch {
      if let opened, let current { try? opened.rollback(matching: current) }
      throw DigitalObjectDownloadFailure(checkpoint: current, reason: Self.downloadError(error))
    }
  }

  /// Executes a reusable resumable request with caller-retained local state.
  /// - Parameters:
  ///   - request: A built-in or consumer-defined resumable request.
  ///   - checkpoint: The earlier local checkpoint.
  ///   - destination: A new same-filesystem file.
  /// - Returns: Complete validated bytes and retained progress evidence.
  /// - Throws: `DigitalObjectDownloadFailure` with the last verified durable checkpoint.
  public func value(
    for request: DigitalObjectRequest<DigitalObjectDownloadReceipt>,
    checkpoint: DigitalObjectDownloadCheckpoint, to destination: URL
  ) async throws(DigitalObjectDownloadFailure) -> DigitalObjectDownloadReceipt {
    switch request.resolution {
    case .endpoint(let endpoint):
      try await send(endpoint, checkpoint: checkpoint, to: destination)
    }
  }

  private static func downloadError(_ error: any Error) -> DigitalObjectsError {
    if error is CancellationError { return .cancelled }
    if let error = error as? DigitalObjectsError { return error }
    if let error = error as? DigitalObjectDownloadStateError { return .downloadState(error) }
    if let error = error as? DigitalObjectRangeError { return .range(error) }
    return .file(error)
  }
}
