# Source verification

The National Archives Catalog dataset was accessed on September 24, 2026 UTC from the [NARA-managed AWS registry](https://registry.opendata.aws/nara-national-archives-catalog/). Five original response bodies and their exact URLs, retrieval instants, HTTP status, headers, byte counts, and SHA-256 hashes are in [fixture attribution](Sources/SwiftNARACatalogBulkTestSupport/Fixtures/attribution.json). No Catalog HTTP API response is used.

## Verified bulk contract

[NARA's bulk guide](https://www.archives.gov/developer/national-archives-catalog-dataset) describes public unsigned downloads and synchronization from `nara-national-archives-catalog`, with descriptions grouped by record group or collection and authority records by type. It describes a March 2026 snapshot and twice-yearly updates. Its older filename examples use `.json`; the captured objects use JSONL, one `record` envelope per physical line. These sampled objects do not establish every object format in the bucket. The SDK lists all objects and downloads selected `.jsonl` keys.

The [S3 ListObjectsV2 contract](https://docs.aws.amazon.com/AmazonS3/latest/API/API_ListObjectsV2.html) uses `IsTruncated` and opaque `NextContinuationToken`, passed unchanged as `continuation-token`. Maximum page size is 1,000. The implementation does not request a delimiter, interpret tokens as offsets, or promise snapshot consistency. Consecutive captured RG11 pages both contain four objects; the second echoes the first token and supplies another. The captured FDR terminal listing contains 395 objects and `IsTruncated=false`. S3 can return malformed XML with HTTP success; parser validation remains mandatory.

## Historical and metadata evidence

The unmodified RG11 shard contains 35 records, including NAID 162246501 (April 8, 1816) and NAID 100358199 (December 26, 1817), with 9 and 7 digital objects respectively. The FDR shard contains seven records, including NAID 122179401 (1933, 25 objects) and NAID 122197642 (1943, 4 objects). It preserves original extracted OCR and contribution metadata.

NAID 122205923 is a metadata-only description with **no `digitalObjects` member in this capture**. Absence is preserved separately from JSON null and an explicit empty array. Tests also exercise an explicitly empty array in a labeled synthetic input. Campaign speeches, election certificates, and state-government descriptions remain in the source data. No presidential-office inclusion policy or cross-provider identity matching is implemented here.

## Rights and restrictions

The registry labels the dataset US Government work. [NARA's use policies](https://www.archives.gov/global-pages/privacy.html) explain that archival holdings can include third-party copyright and donor restrictions. The package's MIT license covers package code, not all linked media. Preserve record-level access/use restrictions, physical restrictions, attribution, and OCR provenance. A successful download does not establish permission to reuse a digital object.

The separate [Catalog API terms](https://www.archives.gov/research/catalog/help/api) prohibit caching or storing API responses and direct bulk users to the dataset. This package uses only the separately published bulk distribution.

## Networking evidence

Public `git ls-remote --tags` verified swifty-networking `1.3.1`, tag object `61a238a34051e0b1e15876291d0eef7bc2b6adfe`, peeled revision `04bbf231eabb95b90a5be786034e07cf351ee1d5`. The package resolves the public URL with a minimum of 1.3.1. Manifest fetching uses the existing `HTTPClient.pages(_:as:decode:next:)`; shard downloads use `streamResponse(_:)`. XML decoding is implemented by this package, with no FoundationXML or third-party XML dependency.

## Fixtures and mutations

Original fixture bodies are never normalized. `attribution.json` contains their SHA-256 checksums. Tests derive explicitly synthetic variants for invalid XML, token cycles, unknown/null JSON values, CRLF, missing terminators, long lines, and malformed JSONL. They do not label synthetic mutations as additional official responses. Unit tests make no live requests.
