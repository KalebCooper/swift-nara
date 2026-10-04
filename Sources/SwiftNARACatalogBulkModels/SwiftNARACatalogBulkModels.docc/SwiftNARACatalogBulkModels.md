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

`CatalogRecord.authorityRecord` projects an `authority`-typed envelope into `CatalogAuthorityRecord`, exposing an open `CatalogAuthorityType`, heading, source notes, source dates through `CatalogDate`, and typed `CatalogNAIDReference` values for related records. A person, organization, topical-subject, geographic-place-name, or specific-records-type authority can supply any evidenced member, and unprojected members remain in `source`. `CatalogRecord.comments`, `.tags`, and `.transcriptions` project the envelope's top-level `record_comment`, `record_tag`, and `record_transcription` arrays into `CatalogContribution` values in source order; `CatalogRecord.contributionMetadata` exposes the matching `metadata_*` arrays separately, never joined to a contribution by position. A contribution's `contributionSource` names a `CatalogContributionSource` such as `.communityMember` or `.naraStaff`. `isAIMachineGenerated` is the source's own flag, not a text-origin guarantee, and a contribution never replaces or corrects a digital object's OCR `extractedText`. Contributors are Catalog users named in `contributor` or `contributors`, not archival creators.

```swift
let shard = try ShardReference(key: "authority-records/person/person-1.jsonl")
let receipt = try await bulk.download(shard, to: destination)
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

`BulkDirectoryQuery` lists the immediate children of one `BulkDirectory`, either `.authorityRecords`, `.collections`, or `.recordGroups`, as an S3 ListObjectsV2 page that `BulkDirectoryCodec` decodes into `BulkDirectoryPage`. A `BulkPartitionReference` retains the exact discovered prefix and its directory; a prefix such as `descriptions/record-groups/rg_11/` is a storage path, never a parsed record group number or NAID, and padding such as `rg_020/` is kept as listed. Discovery proves storage membership only at the moment of listing.

```swift
let query = try BulkDirectoryQuery(directory: .recordGroups)
let page = try BulkDirectoryPage.decode(data)
print(page.prefixes)
let partition = try BulkPartitionReference(directory: .recordGroups, prefix: page.prefixes[0])
```

``ShardCondition`` holds one entity tag exactly as supplied, quotes and any `W/` prefix included, built through the throwing `.ifNoneMatch(_:)` or `.ifMatch(_:)` factory; an empty entity tag, a control character, a leading or trailing space or tab, the wildcard `*`, or a comma throws `ManifestError.invalidQuery`. A consumer sending requests with its own networking reads `ShardCondition.fieldName` for the exact header name to send. `Endpoint.refresh(_:condition:)` and `CatalogBulkRequest.refresh(_:condition:)` describe a conditional shard download the same way `.shard(_:)` describes an unconditional one; an endpoint built from a raw path or a link carries no condition. `ShardRefreshResult` distinguishes `.downloaded(ShardReceipt)` from `.notModified(SourceRetrieval)`; a not-modified result carries only retrieval evidence, with no file, byte count, or receipt. `BulkObjectChange.compare(previous:current:)` is a pure comparison of two `BulkObject` hints by key, ETag, size, and last-modified; `storageClass` is not compared. An unchanged result means no observed metadata change, not verified byte identity, and a key difference means the two hints describe different objects, so any other differing field reported alongside it is not evidence about one object's history.

```swift
let condition = try ShardCondition.ifNoneMatch(previousETag)
let endpoint = Endpoint.refresh(reference, condition: condition)
let request = CatalogBulkRequest.refresh(reference, condition: condition)
```

## Digital-object metadata

`CatalogDigitalObject` preserves source labels through `objectDescription` and
`objectDesignator`, and keeps `completeExtractedText`, `extractedText`, and
`otherExtractedText` separate. The latter is partner text according to the published
schema. `extractedTextAccuracy` reads the provider's `extractedTextAccurracy` integer
without correcting its spelling or clamping its value. `thumbnailURL` preserves a
link even when its host is unsupported for downloading. These properties perform no I/O.

The retained bulk captures evidence descriptions, designators, and complete OCR.
Accuracy, partner text, and thumbnail projections have schema and synthetic-test
coverage only. Missing, null, and wrong-shaped values return nil; inspect `source`
to distinguish them. Neither OCR quality nor reuse permission is inferred.

```swift
for object in record.digitalObjects ?? [] {
  print(object.objectDesignator, object.objectDescription)
  print(object.completeExtractedText, object.otherExtractedText)
  print(object.extractedTextAccuracy, object.thumbnailURL)
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

### Directory discovery
- ``BulkDirectory``
- ``BulkDirectoryCodec``
- ``BulkDirectoryPage``
- ``BulkDirectoryQuery``
- ``BulkPartitionReference``

### Archival descriptions
- ``CatalogAncestor``
- ``CatalogDate``
- ``CatalogDescription``
- ``CatalogDescriptionLevel``
- ``CatalogRestriction``
- ``CatalogRestrictionStatus``

### Authority records
- ``CatalogAuthorityRecord``
- ``CatalogAuthorityType``
- ``CatalogNAIDReference``

### Contributions
- ``CatalogContribution``
- ``CatalogContributionMetadata``
- ``CatalogContributionSource``
- ``CatalogContributionTarget``

### Selective refresh
- ``BulkObjectChange``
- ``ShardCondition``
- ``ShardRefreshResult``

### Provenance
- ``CatalogLine``
- ``ShardReceipt``
- ``SourceHeader``
- ``SourceResponse``
- ``SourceRetrieval``

## Partial-byte evidence

`BulkByteRange` selects one closed interval. `BulkRangeReference` binds a strong
quoted ETag and positive known total length to a validated source.
`BulkRangeReceipt` describes only the saved interval; it is never a complete-file receipt.
Bulk references accept JSONL shard keys or ZIP keys and can pin a meaningful S3 version.
A partial JSONL interval may split a UTF-8 character or record and cannot be read as a shard.
