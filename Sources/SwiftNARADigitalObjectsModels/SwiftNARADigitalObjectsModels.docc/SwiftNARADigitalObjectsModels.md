# ``SwiftNARADigitalObjectsModels``

Describe on-demand original-file and image-information requests without performing I/O.

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

IIIF information has a separate validated service identity. `IIIFImageReference`
derives the observed NARA version-3 mapping from either supported source prefix,
encoding the source key once as one identifier segment. `IIIFImageInformation`
retains raw JSON bytes and projects dimensions, limits, preferred sizes and tile
declarations without fetching tiles, JSON-LD contexts or linked services. Unknown
feature codes and null members remain inspectable in the original bytes.

A validated `IIIFImageRequest` requires explicit information and a positive width,
height or fit box, or the server maximum. Unsupported profiles/features, upscaling,
and advertised limits fail before I/O. Fit bounds must be within original dimensions.
Limit checks round fractional dimensions upward conservatively; `maximum` delegates
to version-3 `max`. The fixed representation is full-region, unrotated default JPEG.
`IIIFImageReceipt` preserves derivative bytes and requested transform separately
from an original-file receipt. No request construction fetches information.

## Topics

### Image derivatives
- ``IIIFImageReceipt``
- ``IIIFImageRequest``
- ``IIIFImageSize``


### Image information
- ``IIIFImageError``
- ``IIIFImageInformation``
- ``IIIFImageReference``


### Requests
- ``DigitalObjectReference``
- ``DigitalObjectReferenceError``
- ``DigitalObjectRequest``
- ``Endpoint``

### Retrieval evidence
- ``DigitalObjectReceipt``

