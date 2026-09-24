# Implementation readiness

The initial NARA bulk slice is implemented locally in `SwiftNARACatalogBulkModels` and `SwiftNARACatalogBulk`. It has no published release. [Source verification](SOURCE_VERIFICATION.md) records official distribution, continuation, object-format, rights, and dependency evidence.

## Implemented scope

- Pure portable S3 XML decoding and validated ListObjectsV2 queries, with exact opaque continuation and same-origin endpoints.
- Everyday methods, reusable typed requests, independent endpoints, and consumer-defined response decoding.
- Shared swifty-networking pagination with bounded page receipts, independent lazy page/object iterators, cancellation, token-cycle detection, and optional record-before-yield persistence.
- Streamed JSONL downloads with byte bounds, HTTP receipts, new-file publication, and partial-file cleanup. Local JSONL reading is a separate bounded lazy operation.
- Exact NAIDs, open source envelopes, hierarchy, digital-object and OCR metadata, restrictions, original line bytes, offsets, and retrieval provenance. Missing digital-object members remain distinct from null and explicit empty arrays.
- Five unchanged official fixtures with attributed URLs, timestamps, status, headers, byte counts, and SHA-256; historical 1816/1817 and FDR examples; typed failures; two DocC catalogs; and an offline command-line demo.

The public swifty-networking 1.3.1 tag was verified before setting the dependency floor. Its custom page decoder and streamed response receipt are used directly. XML support is source-specific and does not assume networking-package XML parsing. The trait-on lockfile records the portable dependency superset.

## Local qualification

Verified September 24, 2026 UTC (September 23 in America/Chicago). Local logs and documentation archives are retained in the ignored `plans/` directory.

| Gate | Evidence and remaining limit |
| --- | --- |
| Source conventions | All 15 checks pass; 47 planted self-test cases pass. Recorded JSONL prose is excluded only inside the fixture directory, with negative coverage for authored JSONL elsewhere. |
| Strict formatting | Sources, Tests, both package manifests, and demo source pass. |
| Linux default and HTTPPortable | 25 tests in 5 suites pass in each configuration, with no compiler warnings, under Swift 6.3.3 in `swift:6.3-noble` (`plans/linux-final.log`). |
| Apple via Xcode MCP | An earlier revision built successfully for iPhone 18 Pro / iOS 27, including build-for-testing. The test operation timed out without results; its log contained two incompatible macOS/iOS sysroot linker warnings. The bridge subsequently returned `Transport closed`, including after reopening this package. The final revision, test execution, and Apple Release demo remain unverified. No shared bridge reset or sibling workspace changes were made. |
| Declared Apple floor | Xcode 26 / Swift 6.2 and the iOS 26 runtime were not qualified locally. |
| Android | No installed Swift Android SDK, adb, or emulator was available. No Android compatibility result is claimed. |
| DocC | Both catalogs convert with warnings treated as errors, models first, using final Linux symbols; merged archive and static site generation also pass (`plans/docc-final/`). Apple-only URLSession documentation remains part of the pending Apple qualification. |
| Release demo | The standalone SwiftPM command-line example builds and runs in the Linux container, reading two manifest pages and seven shard records from recorded responses. |
| Hosted CI and delivery | No hosted run, remote creation, push, tag, release, or Pages deployment was performed. Platform and documentation jobs remain disabled; the source validation job runs the locally passing gate and self-tests. |

## Remaining work

Restore a working Xcode MCP connection and rerun the final Apple build, complete tests, floor checks, Apple DocC, and Release demo. Qualify the Android emulator lane when its SDK and tools are available. Run hosted workflows only after a separate delivery decision, then measure actual job durations before replacing provisional timeouts.

The later full historical inventory is coordinated with GovInfo document work. Independent NARA manifest and shard slices do not depend on that inventory. This implementation does not claim all-history completeness, current-administration coverage, stable snapshots, OCR accuracy, or unrestricted rights. The separate Catalog HTTP API remains excluded from persistent ingestion. Application inclusion policy, cross-provider identity resolution, repository publication, and release approval remain outside this slice.
