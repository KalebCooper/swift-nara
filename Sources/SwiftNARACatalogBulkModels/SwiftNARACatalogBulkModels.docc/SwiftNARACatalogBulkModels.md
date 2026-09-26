# ``SwiftNARACatalogBulkModels``

Describe NARA bulk requests and preserve source metadata without a networking dependency.

## Overview

`ManifestQuery`, `Endpoint`, and `CatalogBulkRequest` are immutable values. `ManifestCodec` reads the public S3 listing as bounded UTF-8 XML with a portable source-specific parser. It does not rely on Codable to parse XML, perform external entity resolution, or import FoundationXML.

`CatalogRecord` keeps the entire open JSON envelope and exposes NAIDs, ancestor metadata, digital-object metadata, restrictions, and original OCR. Unknown members and explicit null values remain in `JSONValue`; inspect `CatalogRecord.fields` when a convenience projection is absent. An explicit empty digital-object array differs from a missing member or null. Metadata-only descriptions remain valid records.

```swift
let query = try ManifestQuery(maxKeys: 4, prefix: "descriptions/record-groups/rg_11/")
let endpoint = Endpoint.manifest(query)
let request = CatalogBulkRequest.manifest(query)
print(endpoint.url, request.resolution)
```

A consumer can execute an endpoint using its own transport and call `BulkManifest.decode` or `CatalogRecord.decode` with the original bytes. Codable conformances on the manifest support persistence of decoded values as JSON, not XML deserialization. Exact bytes in source responses and JSONL lines remain authoritative for numeric spelling, whitespace, unknown XML fields, and replay.

The package preserves archival classifications and source dates without converting them to official-action classifications, normalized dates, or a claim of complete presidential history. ETags are opaque version hints. Reuse of linked media is subject to item-level rights and restrictions.

`CatalogRecord.archivalDescription` projects a `description`-typed envelope into `CatalogDescription`, exposing typed title, level, ancestors, production and inclusive dates, and access/use restrictions over the same `source` rather than replacing it. `CatalogDate` retains the source's `day`, `month`, and `year` components and its `logicalDate` string instead of an invented instant: a year-only date leaves `day` and `month` nil even though `logicalDate` fills in `01-01`. `CatalogRestriction` retains the source's `status` as an open `CatalogRestrictionStatus` code, not a reuse authorization. Records of other or unknown types return `nil`. A description whose `digitalObjects` member is absent, such as NAID 122205923, still projects `archivalDescription`; `CatalogRecord.isMetadataOnly` is `nil` there because availability is undeclared, not `true`, which only an explicit empty array reports.

```swift
for try await line in try CatalogLineSequence(shard: receipt) {
  guard let description = line.record.archivalDescription else { continue }
  print(description.naID, description.levelOfDescription?.rawValue, description.title)
  print(description.productionDates?.first?.year, description.ancestors?.first?.naID)
  print(description.accessRestriction?.status?.rawValue)
  print(line.byteOffset, line.lineNumber, line.shard.retrieval.url)
}
```

## Topics

### Request values
- ``CatalogBulkRequest``
- ``Endpoint``
- ``ManifestQuery``
- ``ShardReference``

### Source decoding
- ``BulkManifest``
- ``BulkObject``
- ``CatalogBulkResponse``
- ``CatalogDecodingError``
- ``CatalogDigitalObject``
- ``CatalogRecord``
- ``JSONValue``
- ``ManifestCodec``
- ``ManifestError``

### Archival descriptions
- ``CatalogAncestor``
- ``CatalogDate``
- ``CatalogDescription``
- ``CatalogDescriptionLevel``
- ``CatalogRestriction``
- ``CatalogRestrictionStatus``

### Provenance
- ``CatalogLine``
- ``ShardReceipt``
- ``SourceHeader``
- ``SourceResponse``
- ``SourceRetrieval``
