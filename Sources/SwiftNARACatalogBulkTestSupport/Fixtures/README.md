# Recorded NARA bulk responses

National Archives Catalog was accessed on September 24, 2026 UTC from the [NARA-managed AWS registry](https://registry.opendata.aws/nara-national-archives-catalog/). Original bytes are retained in every XML and JSONL fixture. See `attribution.json` for exact requests, UTC instants, status, response headers, byte counts, and SHA-256 hashes. The five authority-record fixtures, the five directory listings, and the two conditional responses were accessed on September 26, 2026 UTC from the same bulk origin.

- `manifest-first.xml` and `manifest-second.xml`: consecutive four-object RG11 listings.
- `manifest-terminal.xml`: terminal FDR collection listing, 395 objects.
- `rg11.jsonl`: 35 descriptions including the 1816 and 1817 ratifications.
- `fdr.jsonl`: seven descriptions including 1933 and 1943 material, OCR, campaign material, and metadata-only descriptions.
- `geographic-reference.jsonl`: 32 geographic place name authority records.
- `organization.jsonl`: 156 organization authority records.
- `person.jsonl`: 125 person authority records.
- `specific-records-type.jsonl`: two specific records type authority records.
- `topical-subject.jsonl`: 54 topical subject authority records.
- `directory-collections-first.xml` and `directory-collections-second.xml`: consecutive truncated three-prefix collection listings with a `/` delimiter and no objects.
- `directory-record-groups.xml`: truncated three-prefix record group listing with a `/` delimiter: `rg_1/`, `rg_10/`, `rg_100/`.
- `directory-authority-records.xml`: terminal authority listing with a `/` delimiter: five category prefixes and the zero-byte `authority-records/` object.
- `directory-authority-records-undelimited.xml`: truncated eight-object authority listing without a delimiter, beginning with the zero-byte `authority-records/` object.
- `refresh-not-modified.headers.json`: response headers of the HTTP 304 to a GET of the FDR shard with `If-None-Match` set to the ETag recorded for `fdr.jsonl`. A 304 has no body, so the file holds the headers exactly as received, in order; the attribution entry records a zero byte count, the SHA-256 of the empty body, and the request headers sent.
- `refresh-precondition-failed.xml`: unchanged S3 `PreconditionFailed` error body of the HTTP 412 to a GET of the FDR shard with a mismatched `If-Match`.

These are source data, not coverage claims or a reuse license for linked media. Source restrictions and contribution attribution remain in the captured records. Synthetic edge cases are created and labeled inside tests; they do not replace the original fixtures.
