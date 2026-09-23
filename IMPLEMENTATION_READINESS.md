# Implementation readiness

This repository is an infrastructure scaffold, with no service source, products, dependencies, or release. A scaffold check is not a build or portability result.

## First implementation prerequisite

Complete and verify the shared swifty-networking transport receipt and portable decoding work before starting the government API slice. Select the published dependency version only after that work is available. Do not add provisional dependency pins, the HTTPPortable trait, or empty targets.

The intended product pair is `SwiftNARACatalogBulk` and `SwiftNARACatalogBulkModels`. These names are reserved by the package scope, not declared in the manifest. Verify the official bulk distribution contract and item restrictions before implementation. The separate Catalog HTTP API is excluded from persistent ingestion.

The S3 manifest is paginated XML. Extend the existing swifty-networking paginator with bounded source decoding, preserving its JSON default and shared fetching/continuation machinery before adding the SDK. Verify portable XML decoding and response-byte/metadata receipts for single and paginated responses, including cancellation, early break, and recorder failure without prefetch or refetch.

Stream selected JSONL shards with bounded memory; distinguish network downloads from local record iteration. Never decode the whole bulk corpus as an in-memory array. Preserve NAID, source hierarchy, object URL/key/version metadata, line identity, raw-record evidence, and retrieval provenance. Manifest ETags are version hints, not assumed SHA-256 content digests. Preserve digital-object links, OCR provenance, access/use restrictions, and rights statements; empty digital-object arrays mean metadata-only availability.

Recorded fixtures must cover historical 1816/1817 descriptions, FDR-era material, metadata-only records, unknown fields, nulls, malformed JSONL records, and XML continuation failures. Archival holdings can include campaign material and non-presidential service: preserve source data and leave application inclusion policy to consumers. Do not imply every archived speech is an official presidential action or that a snapshot is a current-administration feed.

## Deferred implementation and verification

- Actual models, endpoints, typed requests, client operations, fixtures, Swift Testing suites, and consumer compile examples.
- HTTPPortable trait forwarding, transport dependencies, and the verified trait-on `Package.resolved` superset.
- Apple build/tests with the generated `swift-nara-Package` scheme through Xcode MCP.
- Linux default and HTTPPortable suites, Android emulator suite, and source formatting. Their retained CI jobs are explicitly disabled.
- One DocC catalog per implemented product, models-first documentation metadata, `.spi.yml`, and zero-warning local DocC builds. Both documentation workflow jobs are disabled.
- A working demo and its release build. Demo CI wiring is retained but disabled with the Apple job.
- Full repository source verification and all platform gates before activating source CI.
- Remote creation, push, hosted CI, tags, and release publication require a separate delivery decision.

`Scripts/verify-source.sh` retains the adapted family gate and its planted-violation self-tests. Source, Linux, and documentation scripts reject absent modules before doing source-dependent work. `Scripts/verify.sh --scaffold` checks only infrastructure; the default command never treats this scaffold as a completed library.
