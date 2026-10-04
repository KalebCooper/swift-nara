# Changelog

All notable changes are documented here, following Keep a Changelog and Semantic Versioning.

## Unreleased

### Added

- Versioned bulk and original-media checkpoint models with validated decoding, Codable range references, and bounded SDK-only SHA-256 prefix hashing. Download lifecycle execution remains pending.

- Bounded original-media and bulk byte ranges with strong validators, optional bulk version pins, strict partial-response validation, and distinct fragment receipts.

- Validated full-image IIIF JPEG resizing with width, height, fit and server-maximum sizes, separate derivative receipts, and bounded file publication.

- Bounded IIIF Image API 3 information with validated source mapping, raw JSON preservation, dimensions, server limits, and retrieval evidence.

- Independent digital-object client with explicit byte budgets, bounded CDN error evidence, new-file publication, four-product documentation, and an offline media demo.

- Digital-object descriptions, designators, complete OCR, partner text, declared accuracy, and thumbnail link projections, preserving raw nulls and unknown fields.

- Independent `SwiftNARACatalogBulkModels` and `SwiftNARACatalogBulk` products using verified swifty-networking 1.3.1 APIs.
- Portable bounded S3 XML decoding, typed manifest requests/endpoints, and lazy page/object traversal with opaque token validation and exact response receipts.
- Streamed JSONL downloads with complete-file receipts, byte bounds, cleanup on failure, and bounded independent local line iteration.
- Open source records preserving NAIDs, hierarchy, digital objects, OCR/contributions, unknown/null fields, metadata-only descriptions, and restrictions.
- Typed archival-description views (`CatalogDescription`, `CatalogAncestor`, `CatalogDescriptionLevel`, `CatalogDate`, `CatalogRestriction`, `CatalogRestrictionStatus`) and `CatalogRecord.archivalDescription`, projecting existing envelopes without changing raw source data.
- Typed authority-record views (`CatalogAuthorityRecord`, `CatalogAuthorityType`, `CatalogNAIDReference`) and `CatalogRecord.authorityRecord`, and typed contribution views (`CatalogContribution`, `CatalogContributionMetadata`, `CatalogContributionSource`, `CatalogContributionTarget`) with `CatalogRecord.comments`, `.tags`, `.transcriptions`, and `.contributionMetadata`, projecting existing envelopes without changing raw source data.
- Bulk directory discovery (`BulkDirectory`, `BulkDirectoryQuery`, `BulkPartitionReference`, `BulkDirectoryPage`, `BulkDirectoryCodec`) and lazy traversal (`DirectoryPageSequence`, `BulkPartitionSequence`) with `CatalogBulkClient.directory(matching:)`, `.directoryPages(matching:)`, and `.partitions(matching:)`; a discovered prefix proves storage membership only at traversal time and is never a National Archives Identifier.
- Conditional shard refresh (`ShardCondition`, `ShardRefreshResult`, `BulkObjectChange`) and `CatalogBulkClient.refresh(_:condition:to:)`, distinguishing a not-modified retrieval from a new download and comparing a saved and a current object listing hint, without retrying or replacing an existing destination file.
- `SwiftNARADigitalObjectsModels` product with `DigitalObjectReference`, which keeps a bulk `objectUrl` unchanged and derives its public `catalog.archives.gov` transport path from the two verified `NARAprodstorage` prefixes, and `DigitalObjectReferenceError`, a typed refusal for every other origin, scheme, credentials, fragments, queries, dot segments, and malformed paths.
- Digital object `Endpoint.download(_:)` and `Endpoint.init?(link:)`, restricted to `/medialz/` and `/medialive/` object paths on `catalog.archives.gov`; `DigitalObjectRequest` with an inspectable `resolution` and a `download(_:)` factory; and `DigitalObjectReceipt`, recording the source reference, transport URL, status, headers in received order, saved byte count, destination, and a caller-supplied retrieval instant, with `mediaType` read only from a received `Content-Type` and `nil` when none was received.
- Attributed original manifest, RG11, and FDR fixtures, deterministic Swift Testing coverage, two DocC catalogs, and an offline command-line demo.
- Provider evidence and explicit qualification status; source validation retains absent-subject and planted-violation coverage.

### Fixed

- Enable Apple, Android, Linux, strict formatting, and DocC build checks on pushes and pull requests.
- Publish the DocC site after successful documentation builds on main.
