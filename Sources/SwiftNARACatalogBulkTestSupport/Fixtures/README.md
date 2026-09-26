# Recorded NARA bulk responses

National Archives Catalog was accessed on September 24, 2026 UTC from the [NARA-managed AWS registry](https://registry.opendata.aws/nara-national-archives-catalog/). Original bytes are retained in every XML and JSONL fixture. See `attribution.json` for exact requests, UTC instants, status, response headers, byte counts, and SHA-256 hashes. The five authority-record fixtures were accessed on September 26, 2026 UTC from the same bulk origin.

- `manifest-first.xml` and `manifest-second.xml`: consecutive four-object RG11 listings.
- `manifest-terminal.xml`: terminal FDR collection listing, 395 objects.
- `rg11.jsonl`: 35 descriptions including the 1816 and 1817 ratifications.
- `fdr.jsonl`: seven descriptions including 1933 and 1943 material, OCR, campaign material, and metadata-only descriptions.
- `geographic-reference.jsonl`: 32 geographic place name authority records.
- `organization.jsonl`: 156 organization authority records.
- `person.jsonl`: 125 person authority records.
- `specific-records-type.jsonl`: two specific records type authority records.
- `topical-subject.jsonl`: 54 topical subject authority records.

These are source data, not coverage claims or a reuse license for linked media. Source restrictions and contribution attribution remain in the captured records. Synthetic edge cases are created and labeled inside tests; they do not replace the original fixtures.
