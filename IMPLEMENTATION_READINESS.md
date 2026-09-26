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
| Apple via Xcode MCP | The generated `swift-nara-Package` scheme builds for testing and all 25 tests pass on iPhone 18 Pro / iOS 27 using Xcode 27. No tests fail, skip, or remain unrun. The build still emits incompatible macOS/iOS sysroot linker warnings for generated test products. The Apple Release demo remains unverified. |
| Android | No installed Swift Android SDK, adb, or emulator was available. No Android compatibility result is claimed. |
| DocC | `Scripts/build-docs.sh` passes using Apple iOS simulator modules built through Xcode MCP. Both catalogs convert with warnings treated as errors, models first; merged archive and static site generation pass, including Apple-only URLSession symbols. |
| Release demo | The standalone SwiftPM command-line example builds and runs in the Linux container, reading two manifest pages and seven shard records from recorded responses. |
| Hosted CI and delivery | The repository exists at `KalebCooper/swift-nara`. [CI run 36247312303](https://github.com/KalebCooper/swift-nara/actions/runs/36247312303) passed source validation while Apple, Android, Linux, and formatting jobs were disabled. [Docs run 36247312312](https://github.com/KalebCooper/swift-nara/actions/runs/36247312312) was skipped. These build checks are now enabled for pushes and pull requests; hosted results for the change are pending. Pages deployment is enabled after successful documentation builds on main. No release is published. |

## Remaining work

Verify the enabled hosted Apple, Android, Linux, formatting, and DocC lanes, including the Apple Release demo and Pages deployment. Android has no local qualification result because its SDK and emulator are unavailable here. Measure actual green main job durations before replacing provisional timeouts. Releases require separate approval.

The later full historical inventory is coordinated with GovInfo document work. Independent NARA manifest and shard slices do not depend on that inventory. This implementation does not claim all-history completeness, current-administration coverage, stable snapshots, OCR accuracy, or unrestricted rights. The separate Catalog HTTP API remains excluded from persistent ingestion. Application inclusion policy, cross-provider identity resolution, repository publication, and release approval remain outside this slice.
