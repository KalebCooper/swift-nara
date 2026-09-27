# ``SwiftNARACatalogBulk``

Traverse NARA bulk manifests, download selected JSONL shards, and read local archival records.

## Overview

`CatalogBulkClient` uses the official public bulk bucket, with no credentials and no Catalog HTTP API calls. Supply your application identity and an injected retrieval clock when creating the client. Apple clients can use the URL session initializer; Linux and Android consumers can supply the portable transport with the `HTTPPortable` trait.

```swift
let query = try ManifestQuery(prefix: "descriptions/record-groups/rg_11/")
let first = try await client.manifest(matching: query)
let same = try await client.value(for: .manifest(query))
let direct = try await client.send(.manifest(query))
```

`manifestPages(matching:)` returns source responses containing the decoded page, exact original bytes, status, headers, source URL, and retrieval instant. `objects(matching:)` exposes the same listing as individual entries. Both defer requests until iteration, keep independent iterators, preserve order and duplicates, and never prefetch. A custom endpoint request yields one page unless it uses the built-in manifest request factory.

```swift
let request = CatalogBulkRequest.manifest(query)
for try await page in client.pages(for: request, record: { response in
  try await archive.save(response.body, from: response.retrieval.url)
}) {
  print(page.value.objects.count)
}
```

The recorder runs once after continuation validation and before delivery. If recording fails, that iterator ends without another request. Invalid, absent, repeated, or mismatched continuation metadata is an error, never quiet completion. Partial traversal is not a complete inventory.

## Download before reading local records

```swift
let reference = try ShardReference(
  key: "descriptions/collections/coll_FDR-FDRMSF/coll_FDR-FDRMSF-1.jsonl")
let receipt = try await client.download(reference, to: destination)
for try await line in try CatalogLineSequence(shard: receipt) {
  print(line.record.naID, line.lineNumber, line.byteOffset)
}
```

Downloads stream to a unique temporary sibling and publish a new destination only after successful completion. Existing files are not replaced. A receipt carries the source URL, headers, retrieval instant, and exact saved byte count. The default total download bound is 1 GiB and can be configured. Redirects, transparent content encodings, and incomplete content lengths are rejected. Automatic retries are disabled; consumers own retry and checkpoint policy.

Local iteration opens the saved file only on the first read and buffers at most one bounded line plus a 64 KiB read chunk. Its default line bound is 8 MiB including the terminator. Each result preserves the original LF/CRLF or missing final terminator, a physical line number, byte offset, source envelope, and download receipt. Malformed and blank lines fail with their original location and end the iterator. No local iteration sends a network request. Keep the file immutable during traversal.

Manifest buffering is capped during receipt, defaulting to 4 MiB. XML nesting is limited to 16 elements. Caller-supplied transports must honor the transport contract and avoid unbounded internal buffering; the SDK cannot control a transport's upstream storage. Download receipts do not claim a cryptographic content digest. Hash the saved bytes when your storage policy requires one; do not substitute S3 ETags for SHA-256.

The bulk distribution is a periodic archival snapshot. The package does not promise current-administration coverage, all-history completeness, stable snapshots, OCR accuracy, or permission to reuse every digital object. Missing digital-object members remain distinguishable from explicit empty arrays and nulls.

## Discover a directory before requesting a partition

```swift
let query = try BulkDirectoryQuery(directory: .recordGroups)
for try await partition in client.partitions(matching: query) {
  let shards = try ManifestQuery(prefix: partition.prefix)
  print(partition.prefix)
}
```

`directory(matching:)` returns one validated `BulkDirectoryPage`; `directoryPages(matching:)` and `pages(for:record:)` give the same lazy source-response traversal the manifest methods use, extended to directory listings. `partitions(matching:)` drains each page's common prefixes before requesting the next page and never yields an object listed directly in the directory, such as a zero-byte marker key equal to the prefix itself. Discovery proves storage membership only at the moment of traversal, never a stable or current snapshot. A discovered prefix is a storage path, not a National Archives Identifier: `descriptions/record-groups/rg_11/` names a partition to list further, not NAID 11.

## Refresh selected shards

```swift
let reference = try ShardReference(key: currentObject.key)
switch try await client.refresh(
  reference, condition: try .ifNoneMatch(previousETag), to: newDestination)
{
case .downloaded(let receipt):
  print(receipt.byteCount, receipt.retrieval)
case .notModified(let retrieval):
  print(retrieval.status)  // keep the consumer's previous file and receipt
}
```

Scheduling, durable inventories, checkpoints, hashing policy, and record reconciliation stay in the consumer: enumerate only the selected prefixes, compare each listed object's key, ETag, size, and last-modified hint against a saved inventory with `BulkObjectChange.compare(previous:current:)`, fetch changed candidates into new destinations, then checkpoint the validated result in consumer storage.

A `304 Not Modified` leaves the destination untouched, creates no file and no temporary file, and reports only retrieval evidence, so the consumer keeps its previous file and receipt. A `412 Precondition Failed` means the source's current entity tag does not match the one supplied; renew the inventory before deciding what to fetch, since the client does not retry. A single `403` or `404` seen while scanning is not evidence of deletion; a full inventory difference is evidence for reconciliation, and reconciliation, including any deletion, stays a consumer decision.

Refreshing to a destination that already exists throws before any request is sent, even when the source would answer 304. `refresh(_:condition:to:)`, `value(for:to:)`, and `send(_:to:)` agree at all three levels. An endpoint built from a raw path or a link carries no condition and is sent unconditionally.

## Topics

### Client operations
- ``CatalogBulkClient``
- ``CatalogBulkConfiguration``
- ``CatalogBulkError``

### Lazy traversal
- ``BulkObjectSequence``
- ``CatalogLineSequence``
- ``ManifestPageSequence``

### Directory discovery
- ``BulkPartitionSequence``
- ``DirectoryPageSequence``
