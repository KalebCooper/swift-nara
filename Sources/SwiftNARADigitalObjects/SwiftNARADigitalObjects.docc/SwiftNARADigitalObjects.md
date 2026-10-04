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

## Topics

### Client
- ``DigitalObjectsClient``
- ``DigitalObjectsConfiguration``
- ``DigitalObjectsError``

