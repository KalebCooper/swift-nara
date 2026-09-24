#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

import HTTPCore
import SwiftNARACatalogBulkModels

// The shared paginator owns fetching; this capture carries decoding evidence to the adapter.
struct ManifestCapture: Sendable {
  let body: Data
  let manifest: BulkManifest
  let retrievedAt: Date
}
