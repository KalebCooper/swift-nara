/// A local checkpoint or ownership condition that prevents safe continuation.
public enum DigitalObjectDownloadStateError: Error, Equatable, Sendable {
  /// The opened partial file no longer has the recorded identity or regular-file shape.
  case fileChanged
  /// The committed prefix no longer matches its recorded SHA-256 digest.
  case integrityMismatch
  /// The sidecar is malformed, incompatible, or bound to another source or file.
  case invalidCheckpoint
  /// The caller did not supply an existing private local directory.
  case invalidWorkspace
  /// Another cooperating operation owns the partial file's exclusive lock.
  case writerConflict
}
