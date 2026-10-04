import Crypto
import Foundation
import HTTPCore
import HTTPTypes
import SwiftNARACatalogBulkModels

extension CatalogBulkClient {
  /// Begins retained acquisition of a known archive without sending a request.
  /// - Parameters:
  ///   - reference: A ZIP range reference with an observed strong validator and total.
  ///   - workspace: An existing caller-controlled stable directory.
  ///   - limits: Explicit complete-byte and working-file budgets.
  /// - Returns: A durable zero-byte checkpoint for the existing resume lifecycle.
  /// - Throws: `CatalogBulkError` for a nonarchive reference, bounds or local failure.
  public func beginArchiveDownload(
    _ reference: BulkRangeReference, in workspace: URL, limits: BulkArchiveDownloadLimits
  ) throws(CatalogBulkError) -> BulkDownloadCheckpoint {
    guard !Task.isCancelled else { throw .cancelled }
    _ = try Self.archiveReference(reference)
    try limits.validateResume(
      rangeBytes: configuration.maximumRangeBytes, totalByteCount: reference.totalByteCount)
    return try beginDownload(reference, in: workspace)
  }

  /// Acquires one complete ZIP under explicit transfer and disk budgets.
  /// - Parameters:
  ///   - reference: One selected archive; discovery is a separate manifest operation.
  ///   - destination: A new local file under an existing stable parent.
  ///   - limits: Explicit budgets with no automatic large-download default.
  /// - Returns: Complete bytes, SHA-256 and source evidence; no entry validation is implied.
  /// - Throws: `CatalogBulkError` for cancellation, status, bounds, identity or file failure.
  public func downloadArchive(
    _ reference: BulkArchiveReference, to destination: URL, limits: BulkArchiveDownloadLimits
  ) async throws(CatalogBulkError) -> BulkArchiveReceipt {
    try await value(for: .archive(reference), to: destination, limits: limits)
  }

  /// Resumes a known ZIP through the validated retained-download executor.
  /// - Parameters:
  ///   - checkpoint: An earlier archive checkpoint; a newer matching sidecar may be loaded.
  ///   - destination: A new same-filesystem local file.
  ///   - limits: Budgets covering the archive, one range fragment and two bounded sidecars.
  /// - Returns: A complete archive receipt retaining progress until explicit discardDownload.
  /// - Throws: `BulkDownloadFailure`; budget failure before verification carries no checkpoint.
  public func resumeArchiveDownload(
    _ checkpoint: BulkDownloadCheckpoint, to destination: URL, limits: BulkArchiveDownloadLimits
  ) async throws(BulkDownloadFailure) -> BulkArchiveReceipt {
    let reference: BulkArchiveReference
    do { reference = try Self.archiveReference(checkpoint.reference) } catch {
      throw BulkDownloadFailure(checkpoint: nil, reason: error)
    }
    return try await value(
      for: .archive(reference), checkpoint: checkpoint, to: destination, limits: limits)
  }

  /// Executes an archive endpoint using caller-retained progress and explicit budgets.
  /// - Parameters:
  ///   - endpoint: An archive factory endpoint matching the checkpoint's key and version.
  ///   - checkpoint: Retained progress to verify.
  ///   - destination: A new same-filesystem local file.
  ///   - limits: Explicit archive and working-file bounds.
  /// - Returns: Complete bytes with the final range's source evidence and full local digest.
  /// - Throws: `BulkDownloadFailure` for invalid state, bounds, HTTP or file failure.
  public func send(
    _ endpoint: Endpoint<BulkArchiveReceipt>, checkpoint: BulkDownloadCheckpoint,
    to destination: URL, limits: BulkArchiveDownloadLimits
  ) async throws(BulkDownloadFailure) -> BulkArchiveReceipt {
    let reference: BulkArchiveReference
    do throws(CatalogBulkError) {
      guard !Task.isCancelled else { throw .cancelled }
      reference = try Self.archiveReference(checkpoint.reference)
      guard endpoint.archiveReference == reference else { throw .invalidConfiguration }
      try limits.validateResume(
        rangeBytes: configuration.maximumRangeBytes,
        totalByteCount: checkpoint.reference.totalByteCount)
    } catch { throw BulkDownloadFailure(checkpoint: nil, reason: error) }
    let completed = try await resumeDownload(checkpoint, to: destination)
    guard let time = completed.checkpoint.lastRetrievedAt else {
      throw BulkDownloadFailure(
        checkpoint: completed.checkpoint, reason: .downloadState(.invalidCheckpoint))
    }
    return BulkArchiveReceipt(
      byteCount: completed.byteCount, checkpoint: completed.checkpoint, fileURL: completed.fileURL,
      reference: reference,
      retrieval: SourceRetrieval(
        headers: completed.checkpoint.lastResponseHeaders, retrievedAt: time,
        status: 206, url: reference.url),
      sha256: completed.checkpoint.prefixSHA256)
  }

  /// Executes one complete archive response without extraction, range fallback or retry.
  /// - Parameters:
  ///   - endpoint: An archive factory endpoint.
  ///   - destination: A new local file; existing files and dangling links are refused.
  ///   - limits: Explicit transfer and logical working-file budgets.
  /// - Returns: A receipt only after complete HTTP 200 bytes synchronize and publish.
  /// - Throws: `CatalogBulkError`; failure removes only the owned temporary file.
  public func send(
    _ endpoint: Endpoint<BulkArchiveReceipt>, to destination: URL, limits: BulkArchiveDownloadLimits
  ) async throws(CatalogBulkError) -> BulkArchiveReceipt {
    guard !Task.isCancelled else { throw .cancelled }
    guard let reference = endpoint.archiveReference, destination.isFileURL,
      destination.host == nil || destination.host == "",
      destination.user == nil, destination.password == nil, destination.port == nil,
      destination.query == nil, destination.fragment == nil,
      destination.standardizedFileURL == destination
    else { throw .invalidConfiguration }
    let maximum = min(limits.maximumByteCount, limits.maximumWorkspaceBytes)
    let manager = FileManager.default
    let temporary = destination.deletingLastPathComponent().appendingPathComponent(
      ".nara-archive-" + UUID().uuidString + ".partial")
    var owned = false
    defer { if owned { try? manager.removeItem(at: temporary) } }
    do {
      guard (try? manager.attributesOfItem(atPath: destination.path)) == nil else {
        throw CocoaError(.fileWriteFileExists)
      }
      try Data().write(to: temporary, options: .withoutOverwriting)
      owned = true
      let handle = try FileHandle(forWritingTo: temporary)
      defer { try? handle.close() }
      let response = try await http.streamResponse(Self.request(endpoint))
      guard response.status.code == 200, response.headers[.contentRange] == nil,
        response.headers[.contentEncoding] == nil
          || response.headers[.contentEncoding]?.lowercased() == "identity"
      else { throw CatalogBulkError.sizeMismatch }
      if let version = reference.versionID {
        guard let name = HTTPField.Name("x-amz-version-id"), response.headers[name] == version
        else {
          throw CatalogBulkError.range(.representationChanged)
        }
      }
      let declaredLength: Int64?
      if let text = response.headers[.contentLength] {
        guard !text.isEmpty, text.utf8.allSatisfy({ $0 >= 48 && $0 <= 57 }),
          let length = Int64(text), length > 0
        else { throw CatalogBulkError.sizeMismatch }
        guard length <= maximum else { throw CatalogBulkError.limitExceeded }
        declaredLength = length
      } else {
        declaredLength = nil
      }
      let retrieval = Self.retrieval(
        headers: response.headers, status: 200, time: retrievalTime(), url: endpoint.url)
      var count: Int64 = 0
      var hash = SHA256()
      for try await chunk in response.body {
        try Task.checkCancellation()
        guard Int64(chunk.count) <= maximum - count else { throw CatalogBulkError.limitExceeded }
        try handle.write(contentsOf: chunk)
        hash.update(data: chunk)
        count += Int64(chunk.count)
      }
      try Task.checkCancellation()
      guard count > 0, declaredLength == nil || declaredLength == count else {
        throw CatalogBulkError.sizeMismatch
      }
      try handle.synchronize()
      try handle.close()
      try manager.moveItem(at: temporary, to: destination)
      owned = false
      return BulkArchiveReceipt(
        byteCount: count, checkpoint: nil, fileURL: destination, reference: reference,
        retrieval: retrieval, sha256: BulkDownloadFile.hexadecimal(hash))
    } catch let error as CatalogBulkError {
      throw error
    } catch let error as TransportError {
      throw CatalogBulkError(error)
    } catch { throw Task.isCancelled ? .cancelled : .file(error) }
  }

  /// Executes a reusable archive request against retained progress.
  /// - Parameters:
  ///   - request: Built-in or consumer-defined archive operation.
  ///   - checkpoint: Local checkpoint to verify.
  ///   - destination: A new same-filesystem destination.
  ///   - limits: Explicit transfer and working-file budgets.
  /// - Returns: A completed archive receipt retaining its checkpoint until discard.
  /// - Throws: `BulkDownloadFailure` as the matching endpoint executor.
  public func value(
    for request: CatalogBulkRequest<BulkArchiveReceipt>, checkpoint: BulkDownloadCheckpoint,
    to destination: URL, limits: BulkArchiveDownloadLimits
  ) async throws(BulkDownloadFailure) -> BulkArchiveReceipt {
    try await send(
      Self.endpoint(for: request), checkpoint: checkpoint, to: destination, limits: limits)
  }

  /// Executes a reusable complete archive request.
  /// - Parameters:
  ///   - request: Built-in or consumer-defined archive operation.
  ///   - destination: A new local file.
  ///   - limits: Explicit transfer and working-file budgets.
  /// - Returns: Complete opaque ZIP bytes and acquisition evidence.
  /// - Throws: `CatalogBulkError` as the matching endpoint executor.
  public func value(
    for request: CatalogBulkRequest<BulkArchiveReceipt>, to destination: URL,
    limits: BulkArchiveDownloadLimits
  ) async throws(CatalogBulkError) -> BulkArchiveReceipt {
    try await send(Self.endpoint(for: request), to: destination, limits: limits)
  }

  private static func archiveReference(_ reference: BulkRangeReference) throws(CatalogBulkError)
    -> BulkArchiveReference
  {
    do { return try BulkArchiveReference(key: reference.key, versionID: reference.versionID) } catch
    { throw .invalidConfiguration }
  }
}
