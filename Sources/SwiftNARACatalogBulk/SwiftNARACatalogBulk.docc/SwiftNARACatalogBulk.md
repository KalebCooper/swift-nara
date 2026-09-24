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

## Topics

### Client operations
- ``CatalogBulkClient``
- ``CatalogBulkConfiguration``
- ``CatalogBulkError``

### Lazy traversal
- ``BulkObjectSequence``
- ``CatalogLineSequence``
- ``ManifestPageSequence``
