# swift-nara

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

Portable Swift models and a resource-bounded SDK for National Archives Catalog bulk data.

## Status

Implements paginated S3 XML manifests, streamed JSONL shard downloads, independent bounded local record iteration, and source-byte/HTTP receipts. Models preserve NAIDs, hierarchy, original dates, unknown fields and nulls, digital-object metadata, OCR and contribution provenance, and access/use restrictions. An absent digital-object member is distinct from null or an empty array; metadata-only descriptions remain accessible. Typed archival-description views (`CatalogDescription`, ancestors, production and inclusive dates, access/use restrictions) project the same envelope; typed dates carry the source's day, month, and year components and its logical-date string rather than an invented instant, and restriction status is an open code, not a reuse authorization. Typed authority-record views (`CatalogAuthorityRecord`, `CatalogAuthorityType`, `CatalogNAIDReference`) project person, organization, topical-subject, geographic-place-name, and specific-records-type authority envelopes over the same source. Typed contribution views (`CatalogContribution`, `CatalogContributionSource`, `CatalogContributionTarget`, `CatalogContributionMetadata`) project the envelope's public comments, tags, and transcriptions; contributors are Catalog users, not archival creators, and OCR, community transcription, and machine-generated text are labeled separately, with none of it certified original text. Bulk directory discovery (`BulkDirectory`, `BulkDirectoryQuery`, `BulkPartitionReference`, `BulkDirectoryPage`, `BulkDirectoryCodec`) lists the immediate children of `authority-records/`, `descriptions/collections/`, and `descriptions/record-groups/`; a discovered prefix proves storage membership only at the moment of listing and is never a parsed record group number or National Archives Identifier. Conditional shard refresh (`ShardCondition`, `ShardRefreshResult`, `BulkObjectChange`) downloads a shard only while its entity tag does or does not still match a previously recorded value, distinguishing a not-modified retrieval from a new download, comparing a saved and a current object listing hint, and never retrying or replacing an existing destination file. Digital object references (`DigitalObjectReference`, `DigitalObjectReferenceError`) keep a bulk `objectUrl` string unchanged and derive its public path on `https://catalog.archives.gov`, mapping only `https://s3.amazonaws.com/NARAprodstorage/lz/` to `/medialz/` and `https://s3.amazonaws.com/NARAprodstorage/opastorage/live/` to `/medialive/`, or accepting a URL already under those public paths; every other origin, credentials, fragments, queries, and dot segments are refused with a typed error, never rewritten or passed through. The mapping is how NARA's Catalog site loads bulk-linked objects, not a published contract. Downloading digital objects is not yet built.

The bulk distribution is a periodic archival snapshot. It does not guarantee current-administration coverage, complete history, stable pagination snapshots, OCR accuracy, or unrestricted reuse of linked media. The separate Catalog HTTP API is never used. Package code is MIT-licensed; source content retains its own rights and restrictions.

This package is unreleased. See [source evidence](SOURCE_VERIFICATION.md) and [verification status](IMPLEMENTATION_READINESS.md) for observed formats, exact fixture provenance, current local checks, and historical hosted qualification.

## Usage

```swift
import Foundation
import SwiftNARACatalogBulk
import SwiftNARACatalogBulkModels

let client = CatalogBulkClient(
  configuration: try CatalogBulkConfiguration(
    userAgent: "(my-archive, contact@example.com)"),
  retrievalTime: { .now }
)
let query = try ManifestQuery(
  maxKeys: 4, prefix: "descriptions/record-groups/rg_11/")

let first = try await client.manifest(matching: query)
let request = CatalogBulkRequest.manifest(query)
let same = try await client.value(for: request)
let direct = try await client.send(.manifest(query))

for try await page in client.manifestPages(matching: query) {
  print(page.retrieval.url, page.value.objects.count)
  break  // No request for the following page.
}
```

`objects(matching:)` provides lazy individual objects. `pages(for:record:)` optionally records each validated response before yielding it. Failed recording or unusable continuation ends that iterator without advancing. Custom endpoints remain usable and do not acquire automatic continuation merely by returning a manifest shape.

`directory(matching:)`, `directoryPages(matching:)`, and `partitions(matching:)` discover a bulk directory's children the same way:

```swift
let directoryQuery = try BulkDirectoryQuery(directory: .recordGroups)
for try await partition in client.partitions(matching: directoryQuery) {
  print(partition.prefix)
  break  // No request for the following partition.
}
```

A discovered prefix such as `descriptions/record-groups/rg_11/` proves storage membership at traversal time only; it is a storage path, not a National Archives Identifier, and is never rewritten or parsed into a number.

Download and local iteration are separate operations:

```swift
let shard = try ShardReference(
  key: "descriptions/collections/coll_FDR-FDRMSF/coll_FDR-FDRMSF-1.jsonl")
let destination = URL(fileURLWithPath: "/your/archive/fdr.jsonl")
let receipt = try await client.download(shard, to: destination)

for try await line in try CatalogLineSequence(shard: receipt) {
  print(line.record.naID, line.lineNumber, line.byteOffset)
  // line.rawBytes preserves the original JSON and terminator.
}
```

`line.record.archivalDescription` projects a `description`-typed record into `CatalogDescription`:

```swift
for try await line in try CatalogLineSequence(shard: receipt) {
  guard let description = line.record.archivalDescription else { continue }
  print(description.naID, description.levelOfDescription?.rawValue, description.title)
  print(description.productionDates?.first?.year, description.ancestors?.first?.naID)
  print(description.accessRestriction?.status?.rawValue)
}
```

`line.record.authorityRecord`, `.comments`, `.tags`, and `.transcriptions` project the same envelope for authority records and their public contributions:

```swift
let shard = try ShardReference(key: "authority-records/person/person-1.jsonl")
let receipt = try await client.download(shard, to: destination)

for try await line in try CatalogLineSequence(shard: receipt) {
  if let authority = line.record.authorityRecord {
    print(authority.naID, authority.authorityType?.rawValue, authority.heading)
  }
  for transcription in line.record.transcriptions ?? [] {
    print(transcription.contribution, transcription.target?.objectID)
    print(transcription.isAIMachineGenerated, transcription.contributionSource?.rawValue)
  }
}
```

Refresh a shard against a previously recorded entity tag instead of re-downloading it unconditionally:

```swift
let reference = try ShardReference(key: currentObject.key)
switch try await client.refresh(
  reference, condition: try .ifNoneMatch(previousETag), to: newDestination)
{
case .downloaded(let receipt):
  print(receipt.byteCount)
case .notModified(let retrieval):
  print(retrieval.status)  // keep the previous file and receipt
}
```

A `304` leaves the destination untouched and creates no file; a `412` means the source's current entity tag does not match the one supplied, calling for renewed inventory rather than a retry. `BulkObjectChange.compare(previous:current:)` compares a saved and a current object listing hint by key, ETag, size, and last-modified to decide which shards are worth refreshing.

The parent directory must exist and the destination must be new. Failures remove only the temporary download; no incomplete receipt is returned. A completed receipt proves HTTP/file completion, not that every JSONL record is valid. Local parsing reports malformed or oversized lines with their original physical location. Default limits are 4 MiB buffered responses, 1 GiB per download, and 8 MiB per line. The local reader uses a read buffer no larger than 64 KiB. ETags are opaque version hints, not SHA-256 digests; hash saved bytes when your storage policy requires a digest.

On Apple platforms, the convenience initializer uses URLSession. With the `HTTPPortable` trait, Linux and Android consumers supply the portable transport. Models and codecs import no third-party networking library.

Digital objects also expose source descriptions, designators, complete OCR, partner text,
declared OCR accuracy, and thumbnail links. Accuracy preserves the provider's
`extractedTextAccurracy` value without clamping it; thumbnails remain unvalidated
metadata. Partner text, accuracy, and thumbnails are supported by the published schema
and synthetic tests, with no occurrence in the retained bulk captures.

On-demand original media downloads use the independent `SwiftNARADigitalObjects` product:

```swift
import SwiftNARADigitalObjects
import SwiftNARADigitalObjectsModels

let media = DigitalObjectsClient(
  configuration: try DigitalObjectsConfiguration(
    maximumErrorBodyBytes: 4096, maximumObjectBytes: 10_000_000,
    userAgent: "(my-archive, contact@example.com)"),
  retrievalTime: receiptClock)
let image = try await media.download(reference, to: newDestination)
```

Everyday `download(_:to:)`, request `value(for:to:)`, and endpoint `send(_:to:)` calls
stream complete original bytes to new files. Real HTML is accepted. An observed CloudFront
Error marker causes a bounded `errorPage` failure; absent markers do not prove authenticity.
Partial transfers are removed. Item-level rights and attribution remain the caller's responsibility.

IIIF Image API 3 information is available on demand through `imageInformation(for:)`,
`value(for: .imageInformation(...))`, and `send(.imageInformation(...))`. Construct
`IIIFImageReference(reference: reference)` from the same validated original source.
Information preserves original JSON bytes, dimensions, limits, preferred sizes, tile
metadata, open feature codes, and retrieval evidence. Identity must exactly match the
derived service; no linked context or service is fetched. The default information
budget is one MiB, configurable independently of object and diagnostic budgets.

Full-image JPEG derivatives require explicit information and a validated size:

```swift
let information = try await media.imageInformation(
  for: IIIFImageReference(reference: reference))
let resize = try IIIFImageRequest(information: information, size: .width(200))
let derivative = try await media.downloadImage(resize, to: newImageDestination)
// Equivalent: media.value(for: .image(resize), to: newImageDestination)
// Equivalent: media.send(.image(resize), to: newImageDestination)
```

Width, height and fit requests reject unsupported features, upscaling and exceeded
server limits before I/O. Fit bounds must also stay within original dimensions;
limit calculations round upward conservatively. `maximum` sends version-3 `max`,
allowing the service's advertised limits to produce a smaller image. Only full
region, zero rotation, default quality and JPEG are supported. No operation silently
fetches information or falls back to an original. Derivative receipts preserve the
information identity, requested transform and actual transfer separately.
Declared media type must be JPEG when present; absence stays nil. A checked JPEG
start signature is not complete image decoding or proof of output dimensions.

## Example

[SwiftNARACatalogBulkDemo](Examples/SwiftNARACatalogBulkDemo) is an offline command-line demonstration of two manifest pages, a streamed shard download, and seven provenance-bearing local records. It uses unchanged official fixtures and makes no live request. `bash Scripts/demo-linux.sh` builds it for Release and runs it in the Linux verification container.

[SwiftNARADigitalObjectsDemo](Examples/SwiftNARADigitalObjectsDemo) replays the attributed
FDR JPEG, IIIF information and a 200-pixel-wide derivative, printing source and transport identities, original dimensions and separate derivative byte evidence. Run it offline with
`bash Scripts/demo-media-linux.sh`.

## Products

| Product | Contents |
| --- | --- |
| `SwiftNARACatalogBulk` | Client, lazy manifest/object sequences, downloads, and local JSONL iteration. |
| `SwiftNARACatalogBulkModels` | Source models, pure codecs, validated query/reference values, typed endpoints and requests, and portable provenance. |
| `SwiftNARADigitalObjects` | Bounded original and resized JPEG downloads, IIIF information, typed failures, and retrieval evidence. |
| `SwiftNARADigitalObjectsModels` | Validated original and IIIF references, image information, resize values, requests, endpoints, and receipts. |

## Requirements

Swift tools 6.2 or later, Swift 6 language mode, and iOS/macOS/tvOS/visionOS/watchOS 26 deployment floors. The SDK requires swifty-networking 1.3.1 or later. Default traits are empty. Verification uses Swift Testing, strict swift-format, Xcode MCP on Apple platforms, and the repository Linux/DocC scripts. See the readiness report for which gates actually ran.

## Installation

No public release is published yet. Use a local SwiftPM dependency while evaluating this checkout:

```swift
.package(path: "/path/to/swift-nara")
```

Select either product for your target. Enable `HTTPPortable` explicitly when using the optional portable transport; the tracked lockfile preserves the trait-enabled dependency graph.

## License

MIT. See [LICENSE](LICENSE). This license grants no rights to upstream archival content or linked digital objects.
