# ``SwiftNARADigitalObjects``

Retrieve one original NARA media object with explicit byte budgets and completion evidence.

## Overview

`DigitalObjectsClient` executes the models product's everyday, request, and endpoint
call forms through one streamed executor. It sends no API credentials, follows no
redirects and retries nothing. Each file download requires a new destination under an existing
parent directory. Failed transfers remove only their owned sibling temporary file.

```swift
let configuration = try DigitalObjectsConfiguration(
  maximumErrorBodyBytes: 4096, maximumObjectBytes: 10_000_000,
  userAgent: "(my-archive, contact@example.com)")
let client = DigitalObjectsClient(configuration: configuration, retrievalTime: receiptClock)
let receipt = try await client.download(reference, to: destination)
// Equivalent operations, each requiring its own new destination:
// client.value(for: .download(reference), to: destination)
// client.send(.download(reference), to: destination)
print(receipt.byteCount, receipt.transportURL, receipt.mediaType)
```

Apple's convenience initializer uses URLSession. Other platforms supply an explicit
transport; the HTTPPortable trait enables the portable transport dependency.
The transport must honor redirect refusal and cancel fetching when its body is dropped.

## Response validation

Only a complete HTTP 200 body without Content-Range and without nonidentity encoding
can be published. Declared length and received bytes must agree and both respect the
object budget. Bulk objectFileSize is never used as a transfer bound or expected length.

Real archival HTML is permitted and is never executed here. A successful response
bearing the observed case-insensitive `X-Cache: Error from cloudfront` marker throws
`DigitalObjectsError.errorPage` with status, headers, bounded bytes and a truncation
flag. This is an unpublished CDN convention; an absent or changed marker may allow a
substituted page through. No receipt certifies authenticity or reuse rights.

Non-success responses remain `DigitalObjectsError.transport` with HTTP status evidence.
Their diagnostic bytes are bounded independently of the object budget. A receipt is
returned only after complete bytes have been moved to a new destination. Downloading
does not grant permission to reuse the object; consumers retain item-level attribution
and restrictions from their metadata source.

## Image information

`imageInformation(for:)`, `value(for:)` and `send(_:)` retrieve validated IIIF
Image API 3 information with a separate configurable byte budget. Use an
`IIIFImageReference` derived from a validated original reference. Successful
information includes unchanged JSON, source identity, received headers and injected
retrieval time. Invalid identity, version, dimensions, or JSON fails without
following any advertised link. Original downloads remain a separate operation.

## JPEG derivatives

`downloadImage(_:to:)`, `value(for:to:)` and `send(_:to:)` execute a validated
`IIIFImageRequest`. Obtain information explicitly, then select width, height, fit
or server maximum. Transfers use the object budget and the same new-file lifecycle.
Each call requests only the derivative, without original fallback.

When a media type is supplied it must be `image/jpeg`; absence remains nil in the
receipt. The JPEG start signature is checked across stream chunks before publication.
This detects HTML substitutions without a CDN marker, but is not full image decoding
or confirmation of dimensions. The receipt preserves the original reference,
information identity, requested transform and actual response evidence.

## Topics

### Client
- ``DigitalObjectsClient``
- ``DigitalObjectsConfiguration``
- ``DigitalObjectsError``


## Retrieve a bounded byte interval

```swift
let range = try DigitalObjectByteRange(lowerBound: 16, upperBound: 47)
let fragment = try await client.downloadRange(range, of: knownOriginal, to: destination)
let request = DigitalObjectRequest.range(range, of: knownOriginal)
```

Supply a range reference with an already-observed strong ETag and complete length.
The operation performs one request with `If-Match`, `Range`, and `Accept-Encoding: identity`.
It requires 206, the exact expected interval and total, an unchanged validator, and an exact
saved-byte count. The requested end may be clipped to the known EOF. A 200 is a
`rangeNotHonored` failure; 412 and 416 retain their transport status. Nothing retries or
appends to a previous file. Existing destinations are refused, and failure cleans up the
owned temporary. The default per-range bound is four MiB, separate from complete downloads.

Caller-supplied transports must preserve response representation metadata, honor identity
encoding, refuse redirects, and avoid unbounded buffering. A transport that silently rewrites
both bytes and metadata cannot supply verifiable range evidence.

## Retain validated progress across interruptions

```swift
let checkpoint = try client.beginDownload(knownOriginal, in: privateWorkspace)
let completed = try await client.resumeDownload(checkpoint, to: newDestination)
try client.discardDownload(completed.checkpoint)
```

Begin performs only local I/O. The reference's known total length is the explicit
whole-download budget; the configured range bound limits each serial request.
`value(for:checkpoint:to:)` and `send(_:checkpoint:to:)` execute the same
`.resumableDownload(_:)` request and endpoint. Requests never store file handles or do I/O.
A `DigitalObjectDownloadFailure` carries the last verified durable checkpoint, or nil when
verification did not finish. Retain the initial checkpoint too: the matching sidecar
can contain newer progress after a crash or interrupted checkpoint write.

Resume checks file identity and the committed prefix SHA-256, discards an uncommitted
tail, and only appends validated 206 ranges. Bytes synchronize before each atomic sidecar
advance. A 200 requires a caller-selected fresh start; 412/416 and changed or unverifiable
representations fail without retry. A fully verified complete partial can publish locally
without a further request. No partial receipt promises a complete representation.

Keep the workspace and destination parent stable and private. No-follow opening, inode
and device checks, and advisory locking coordinate SDK writers, but cannot prevent an
external process from mutating files. SHA-256 verifies local continuity, not authenticity.
Publication creates a new same-filesystem hard link without replacement. Owned state
remains until discard; discard removes only the bound partial and sidecar, leaving the
complete destination, private directory, and unrelated files intact. Do not mutate the
published bytes before discarding their retained hard link. A directory-sync failure after
linking can report failure with a complete destination already present. Failed begin may
leave a private child directory for inspection and cleanup. Ordinary downloads retain
their cleanup-on-failure behavior. IIIF derivative resume is not supported.
