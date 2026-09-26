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

Reverified September 26, 2026 UTC. Earlier qualification logs and documentation archives are retained in the ignored `plans/` directory.

| Gate | Evidence and remaining limit |
| --- | --- |
| Source conventions | All 15 checks pass; 47 planted self-test cases pass. Recorded JSONL prose is excluded only inside the fixture directory, with negative coverage for authored JSONL elsewhere. |
| Strict formatting | Sources, Tests, both package manifests, and demo source pass. |
| Linux default and HTTPPortable | 25 tests in 5 suites pass in each configuration, with no compiler warnings, using `bash Scripts/linux-test.sh` and `swift:6.3-noble`. |
| Apple via Xcode MCP | The generated `swift-nara-Package` scheme builds for testing and all 25 tests pass on iPhone 18 Pro / iOS 27 using Xcode 27. No tests fail, skip, or remain unrun. The local build still emits incompatible macOS/iOS sysroot linker warnings for generated test products. Apple Release demo verification is hosted, as recorded below. |
| Android | No installed Swift Android SDK, adb, or emulator was available locally. Hosted emulator qualification is recorded below. |
| DocC | `Scripts/build-docs.sh` passes using Apple iOS simulator modules built through Xcode MCP. Both catalogs convert with warnings treated as errors, models first; merged archive and static site generation pass, including Apple-only URLSession symbols. |
| Release demo | The standalone SwiftPM command-line example builds and runs in the Linux container, reading two manifest pages and seven shard records from recorded responses. |

## Hosted qualification

Verified September 26, 2026 UTC at commit `9b0e9974888e955fe6674ed63340cf5b128c3dda`. [CI run 36249214603](https://github.com/KalebCooper/swift-nara/actions/runs/36249214603) and [Docs run 36249214583](https://github.com/KalebCooper/swift-nara/actions/runs/36249214583) pass with all seven jobs successful and none skipped. Pages deployment initially failed because the repository had no Pages configuration; after enabling Actions-based Pages, the failed deployment passed on retry.

| Gate | Hosted evidence |
| --- | --- |
| Android | All 25 tests in 5 suites pass on the x86_64 emulator with Swift 6.3.3 and HTTPPortable; the complete job takes 4 minutes 50 seconds. |
| Apple | All 25 tests pass on iPhone 18 Pro / iOS 27 with Xcode 27. The Release demo builds and reads seven recorded local records. The complete job takes 4 minutes 48 seconds. |
| DocC | Both catalogs build with warnings treated as errors, merge, and produce the Pages artifact. The build job takes 1 minute 44 seconds. |
| Linux | All 25 tests in 5 suites pass in both HTTPPortable and default configurations. The complete job takes 3 minutes 36 seconds. |
| Pages | Actions-based deployment passes and publishes the [documentation site](https://kalebcooper.github.io/swift-nara/). The deployment job takes 12 seconds. |
| Source conventions | Source validation and all 47 planted gate self-tests pass. |
| Strict formatting | Sources, tests, and demo source pass hosted strict lint. |

## Remaining work

The retained CI and documentation gates are qualified. Job durations above provide the first measured green main baseline for future timeout adjustments. No release is published; tagging and releases require separate approval.

The later full historical inventory is coordinated with GovInfo document work. Independent NARA manifest and shard slices do not depend on that inventory. This implementation does not claim all-history completeness, current-administration coverage, stable snapshots, OCR accuracy, or unrestricted rights. The separate Catalog HTTP API remains excluded from persistent ingestion. Application inclusion policy, cross-provider identity resolution, and release approval remain outside this slice.
