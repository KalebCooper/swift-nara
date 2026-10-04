# Source verification

The National Archives Catalog dataset was accessed on September 24, 2026 UTC from the [NARA-managed AWS registry](https://registry.opendata.aws/nara-national-archives-catalog/). Five original response bodies and their exact URLs, retrieval instants, HTTP status, headers, byte counts, and SHA-256 hashes are in [fixture attribution](Sources/SwiftNARACatalogBulkTestSupport/Fixtures/attribution.json). No Catalog HTTP API response is used. Five authority-record bodies, five directory listings, and two conditional responses were added on September 26, 2026 UTC from the same bulk origin with the same attribution fields; the conditional entries also record the request method and headers.

## Verified bulk contract

[NARA's bulk guide](https://www.archives.gov/developer/national-archives-catalog-dataset) describes public unsigned downloads and synchronization from `nara-national-archives-catalog`, with descriptions grouped by record group or collection and authority records by type. It describes a March 2026 snapshot and twice-yearly updates. Its older filename examples use `.json`; the captured objects use JSONL, one `record` envelope per physical line. These sampled objects do not establish every object format in the bucket. The SDK lists all objects and downloads selected `.jsonl` keys.

The [S3 ListObjectsV2 contract](https://docs.aws.amazon.com/AmazonS3/latest/API/API_ListObjectsV2.html) uses `IsTruncated` and opaque `NextContinuationToken`, passed unchanged as `continuation-token`. Maximum page size is 1,000. The implementation does not request a delimiter, interpret tokens as offsets, or promise snapshot consistency. Consecutive captured RG11 pages both contain four objects; the second echoes the first token and supplies another. The captured FDR terminal listing contains 395 objects and `IsTruncated=false`. S3 can return malformed XML with HTTP success; parser validation remains mandatory.

## Historical and metadata evidence

The unmodified RG11 shard contains 35 records, including NAID 162246501 (April 8, 1816) and NAID 100358199 (December 26, 1817), with 9 and 7 digital objects respectively. The FDR shard contains seven records, including NAID 122179401 (1933, 25 objects) and NAID 122197642 (1943, 4 objects). It preserves original extracted OCR and contribution metadata.

NAID 122205923 is a description whose digital objects are not declared: it has **no `digitalObjects` member in this capture**, so it is not reported as metadata-only, which only an explicit empty array indicates. Absence is preserved separately from JSON null and an explicit empty array. Tests also exercise an explicitly empty array in a labeled synthetic input. Campaign speeches, election certificates, and state-government descriptions remain in the source data. No presidential-office inclusion policy or cross-provider identity matching is implemented here.

## Authority record evidence

A ListObjectsV2 listing of each `authority-records/<type>/` prefix located the first shard of all five authority categories, and each fixture is the unmodified body of that object: `geographic-reference-1.jsonl` (31,042 bytes, 32 records), `organization-1.jsonl` (392,792 bytes, 156 records), `person-1.jsonl` (121,358 bytes, 125 records), `specific-records-type-1.jsonl` (537 bytes, two records), and `topical-subject-1.jsonl` (22,572 bytes, 54 records). Directory and file names are singular and end in `.jsonl`, unlike some examples in the bulk guide. Every line is one envelope whose `record` has `recordType` `authority`, a `naId`, a `heading`, and an `authorityType` of `geographicPlaceName`, `organization`, `person`, `specificRecordsType`, or `topicalSubject`. The first NAIDs are 485327416, 486117330, 470787114, 539925846, and 10636684 respectively. `preferred` is present in every record except four organization records. Other members vary by category. Envelopes in every category except specific records type can carry `record_tag` and `metadata_tag` contributions alongside the record, and some topical subject envelopes also carry `record_comment` and `metadata_comment`. Each object's ETag appears among its recorded response headers; an ETag is S3 object metadata and is not the SHA-256 of the captured bytes. These first shards show record shapes only; they establish no completeness for any authority category.

## Directory listing evidence

Five unsigned ListObjectsV2 responses were recorded unchanged, each HTTP 200 with `application/xml`. With `delimiter=/`, S3 echoes `<Delimiter>/</Delimiter>` and reports child directories as `CommonPrefixes` entries, each with one `Prefix`, in lexical order. `KeyCount` counts prefixes and objects together. The first `descriptions/collections/` page with `max-keys=3` holds only three prefixes (`coll_1AV/`, `coll_AAS/`, `coll_AASA/`), zero objects, and `IsTruncated=true` with a `NextContinuationToken`. The continuation page, fetched with that token exactly as returned, echoes it as `ContinuationToken`, holds the next three prefixes (`coll_AAW/`, `coll_ABC/`, `coll_ABDIL/`), and is also truncated. A truncated page can therefore contain prefixes and no objects. The token is opaque and is recorded verbatim in the attributed URL. The `descriptions/record-groups/` page with `max-keys=3` lists `rg_1/`, `rg_10/`, and `rg_100/`: the order is lexical, not numeric. Neither description listing includes a directory marker object.

The `authority-records/` page with `delimiter=/` and `max-keys=20` is terminal (`IsTruncated=false`) and has `KeyCount` 6: the five category prefixes and one `Contents` object, the zero-byte key `authority-records/` itself with ETag `d41d8cd98f00b204e9800998ecf8427e`. The same prefix listed without a delimiter and with `max-keys=8` starts with that zero-byte marker, followed by seven `geographic-reference` shards. A directory page can therefore carry objects, including its own marker, alongside its prefixes. The objects are separate from the prefixes and are not child directories.

## Conditional request evidence

Two unsigned GET requests for `descriptions/collections/coll_FDR-FDRMSF/coll_FDR-FDRMSF-1.jsonl` were recorded unchanged on September 26, 2026 UTC. The validator is the ETag `"4ee6006efb1a7923711c088aaf8626a0"` recorded with the `fdr.jsonl` capture on September 24; the shard was not fetched again. With `If-None-Match` set to that ETag, S3 returned HTTP 304 with an empty body and no `Content-Length` or `Content-Type`. The response repeated the same ETag, `Last-Modified` (Thu, 09 Apr 2026 17:28:28 GMT), and `x-amz-version-id` (`UJyiii_Crdud2H8tsuMrokVKx2zzjm.6`) as the September 24 capture, which shows that the object's metadata had not changed between the two dates. It does not verify the bytes. With `If-Match` set to the non-matching `"0000000000000000000000000000dead"`, S3 returned HTTP 412 with `application/xml` and a 348-byte `Error` document: `Code` `PreconditionFailed`, `Condition` `If-Match`, and the request and host identifiers. The 412 carried no ETag, `Last-Modified`, or version id, so it does not reveal the object's current validator. The attribution entries state the exact request headers sent, including the conditional one.

## Digital object access

Every `objectUrl` in the recorded bulk shards points at `https://s3.amazonaws.com/NARAprodstorage/`, which refuses unsigned requests with HTTP 403. NARA's Catalog site loads the same objects from `https://catalog.archives.gov`, mapping the bulk prefix `NARAprodstorage/lz/` to `/medialz/` and `NARAprodstorage/opastorage/live/` to `/medialive/`. The site's own live record for NAID 100358199 carries the `/medialz/` URL, and NARA's bulk download pages publish `/medialz/` links. The correspondence is observed practice, not a written contract in the dataset documentation, and `https://catalog.archives.gov/robots.txt` disallows crawling the whole host. Downloads are therefore on demand, one object per call, never a mirror.

Three unsigned requests were recorded on September 27, 2026 UTC and four more on September 28, 2026 UTC, with the attribution fields above plus the request method and headers, in [digital object attribution](Sources/SwiftNARADigitalObjectsTestSupport/Fixtures/attribution.json). No redirect was followed and none was returned.

- A GET of `/medialz/presidential-libraries/roosevelt/577534/msf00611_Page_01.jpg` returned HTTP 200 `image/jpeg` with a 65,981-byte JFIF body, equal to the `objectFileSize` of `objectId` 122178162 in the FDR shard. The response came from a CloudFront cache and passes through S3 object headers: ETag `"03353e5c57368192275f91e5eed396df"`, `Last-Modified` Mon, 04 Mar 2019 15:49:31 GMT, and `Content-Disposition: attachment`. The ETag is not the SHA-256 of the body, and the cached `Date` precedes the retrieval instant.
- A HEAD of `/medialive/5/5458/63545805/content/TB149/M1518/M1518_0007/images/0065.jpg` (`objectId` 63545806 in the RG11 shard) returned HTTP 200 with `Content-Length: 2299069` and no `Content-Type` header. A response's media type can therefore be absent and must not be guessed.
- A GET of a key chosen not to exist under the same `/medialz/` series prefix returned HTTP 200 `text/html` with `X-Cache: Error from cloudfront` and the 5,454-byte Catalog web application page as its body. A missing object is not reported as a 403 or 404, so a 200 status alone does not show that an object was served.
- A GET of a key chosen not to exist under the `/medialive/` prefix of the headers-only object returned the same response: HTTP 200 `text/html`, `X-Cache: Error from cloudfront`, and a 5,454-byte body byte-identical to the `/medialz/` one, with the same ETag and `Last-Modified`. A missing `/medialive/` key behaves like a missing `/medialz/` key.
- A HEAD of `/medialz/electronic-records/rg-341/ALOREPMACAL/AL1.6809.ARLAY.html` (`objectId` 160924454, `objectType` `HTML`, NAID 1129195) returned HTTP 200 `text/html`, `Content-Length: 41948` (its `objectFileSize`), `Content-Disposition: attachment`, and `X-Cache: Miss from cloudfront`.
- A HEAD of `/medialive/28/8797/26879728/content/electronic-records/rg-267/appellate/96-289.HTM` (`objectId` 26879729, `objectType` `HTML`, NAID 26879728) returned HTTP 200 `text/html`, `Content-Length: 2477` (its `objectFileSize`), no `Content-Disposition`, and `X-Cache: Miss from cloudfront`.
- A HEAD of `/medialz/dc-metro/rg-011/299798/RIT_March_2020/162246501/162246501-004_ma.tif` (`objectId` 171484703 in the RG11 shard), a TIFF master not requested by this package before, returned HTTP 200 `image/tiff`, `Content-Length: 606560908`, and `X-Cache: Miss from cloudfront`. Its ETag, `"a70901bcff19a4987bac6122f262eeb0-73"`, is a multipart upload ETag and is not a digest of the body.

Real archival objects can be HTML. To find one, all 360,249 keys under `descriptions/` in the bulk bucket were listed on September 28, 2026 UTC, and the first 524,288 bytes of the first shard of each of the 551 record groups were read with unsigned ranged GET requests; no shard was stored. Those shard heads contain 117 digital objects with `objectType` `HTML` (115 in `rg_267-1.jsonl`, 2 in `rg_341-1.jsonl`) and none with `World Wide Web Page`, the example value in the Catalog schema. This bounded sample establishes that HTML objects exist, not how many there are. The two HTML objects above come from those shards; each bulk shard's ETag and version id at capture are in the attribution entries, and both records' access and use restrictions are `Unrestricted`.

Across all recorded responses, the two signals that distinguish a substituted page from a served object behave as follows. `X-Cache` was `Error from cloudfront` on both missing-object responses and `Hit from cloudfront` or `Miss from cloudfront` on all five real objects; no real object's `X-Cache` began with `Error`. `Content-Type` was `text/html` on both missing-object responses and also on both real HTML objects; it was `image/jpeg`, `image/tiff`, or absent on the other real objects. A `text/html` media type therefore does not distinguish a missing object from a real HTML object, while the `X-Cache` value did in every recorded response. `X-Cache` is set by NARA's CDN and is not part of any published contract.

Bulk `objectFileSize` is not a reliable expected length: 16 of the 36 `lz/` objects in the RG11 shard carry the value `12345678`, and `100358199-001_ac.jpg`, recorded with that value, answered an unsigned HEAD on September 27, 2026 UTC with `Content-Length: 7632855`.

The downloaded object belongs to NAID 122178160, whose record-level access and use restrictions are both `Unrestricted`. Its digital object entry has no restriction member of its own, and the Catalog schema defines none for digital objects. The headers-only object belongs to NAID 63545805, also `Unrestricted` at record level, and is described as an image provided by Fold3; none of its bytes are stored. The other headers-only objects belong to NAIDs 1129195, 26879728, and 162246501, each `Unrestricted` for access and use at record level with no object-level restriction member; none of their bytes are stored.

## Original-media implementation evidence

The October 4 implementation reuses the unchanged September 27-28 captures.
JPEG transfer tests compare all 65,981 original bytes across the three public call forms.
Both 5,454-byte substituted pages exercise bounded error capture. Recorded HEAD headers
for HTML and absent Content-Type are paired only with explicitly synthetic bodies and
adjusted lengths; no HTML GET or Fold3 media fixture is claimed. HTTP failures, byte and
encoding inconsistencies, cancellation, destination races and malformed inputs are synthetic.
The current public API terms and use policies were rechecked; live Catalog API content
remains excluded from persistence and all examples remain offline.

## Digital-object metadata verification

On October 4, 2026, the public [v2 schema](https://catalog.archives.gov/api/v2/swagger.json)
was read without credentials: 202,134 bytes, SHA-256
`9686559b9a2a7a4e1788a7428e551d80ddcc9bc4a73af8b4e1e7e2b515d80238`.
Its digitalObject definition retains `objectDescription`, `objectDesignator`,
`otherExtractedText`, `thumbnailUrl`, and integer `extractedTextAccurracy`.
The unchanged RG11 capture has 58 objects, 38 descriptions, 22 designators, and three
complete-extracted-text values; FDR has 53 objects and four complete-extracted-text
values. Neither capture supplies accuracy, partner text, or thumbnails, so these
projections use explicitly synthetic schema-grounded tests. Complete OCR is evidenced
by the bulk captures, not that schema definition. Original fixture bytes are unchanged.

The bulk guide now publishes September 14, 2026 ZIP links while still describing the
March 1 snapshot in its overview. Earlier March archive sizes, validators, and member
observations remain historical evidence; they do not qualify the newly linked archives.

## Rights and restrictions

The registry labels the dataset US Government work. [NARA's use policies](https://www.archives.gov/global-pages/privacy.html) explain that archival holdings can include third-party copyright and donor restrictions. The package's MIT license covers package code, not all linked media. Preserve record-level access/use restrictions, physical restrictions, attribution, and OCR provenance. A successful download does not establish permission to reuse a digital object.

The separate [Catalog API terms](https://www.archives.gov/research/catalog/help/api) prohibit caching or storing API responses and direct bulk users to the dataset. This package uses only the separately published bulk distribution.

## Networking evidence

Public `git ls-remote --tags` verified swifty-networking `1.3.1`, tag object `61a238a34051e0b1e15876291d0eef7bc2b6adfe`, peeled revision `04bbf231eabb95b90a5be786034e07cf351ee1d5`. The package resolves the public URL with a minimum of 1.3.1. Manifest fetching uses the existing `HTTPClient.pages(_:as:decode:next:)`; shard downloads use `streamResponse(_:)`. XML decoding is implemented by this package, with no FoundationXML or third-party XML dependency.

## Fixtures and mutations

Original fixture bodies are never normalized. `attribution.json` contains their SHA-256 checksums. Tests derive explicitly synthetic variants for invalid XML, token cycles, unknown/null JSON values, CRLF, missing terminators, long lines, and malformed JSONL. They do not label synthetic mutations as additional official responses. Unit tests make no live requests.
