# ``SwiftNARADigitalObjectsModels``

Describe one on-demand original-file request without performing network or file I/O.

## Overview

`DigitalObjectReference` retains the source URL, NAID and object ID separately from
its narrowly validated public transport URL. Only the two evidenced NARA storage
prefixes and their public media equivalents are supported. Availability and rights
are not inferred from a link, declared size or source restriction label.

```swift
let reference = try DigitalObjectReference(
  naID: "122178160", objectID: "122178162",
  url: "https://s3.amazonaws.com/NARAprodstorage/lz/presidential-libraries/roosevelt/577534/msf00611_Page_01.jpg")
let request = DigitalObjectRequest.download(reference)
let endpoint = Endpoint.download(reference)
print(request.resolution, endpoint.url)
```

An endpoint constructed from a public media link has no source identity.
`DigitalObjectReceipt` records actual status, ordered headers, byte count,
destination and injected retrieval instant. Missing Content-Type stays nil;
ETags are opaque validators. The package license does not grant rights to media.

## Topics

### Requests
- ``DigitalObjectReference``
- ``DigitalObjectReferenceError``
- ``DigitalObjectRequest``
- ``Endpoint``

### Retrieval evidence
- ``DigitalObjectReceipt``

