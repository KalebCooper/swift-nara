# Implementation readiness

The initial NARA bulk slice is implemented locally in `SwiftNARACatalogBulkModels` and `SwiftNARACatalogBulk`. It has no published release. [Source verification](SOURCE_VERIFICATION.md) records official distribution, continuation, object-format, rights, and dependency evidence.

## Implemented scope

- Pure portable S3 XML decoding and validated ListObjectsV2 queries, with exact opaque continuation and same-origin endpoints.
- Everyday methods, reusable typed requests, independent endpoints, and consumer-defined response decoding.
- Shared swifty-networking pagination with bounded page receipts, independent lazy page/object iterators, cancellation, token-cycle detection, and optional record-before-yield persistence.
- Streamed JSONL downloads with byte bounds, HTTP receipts, new-file publication, and partial-file cleanup. Local JSONL reading is a separate bounded lazy operation.
- Exact NAIDs, open source envelopes, hierarchy, digital-object and OCR metadata, restrictions, original line bytes, offsets, and retrieval provenance. Missing digital-object members remain distinct from null and explicit empty arrays.
- Typed archival-description views over the same envelope: `CatalogRecord.archivalDescription` projects `description` records into `CatalogDescription` with ancestors, production and inclusive dates, and access/use restrictions. Dates keep the source's day, month, year, and logical-date string without inventing an instant; restriction status is an open code, not a reuse authorization. Absent, null, and wrong-shaped members project `nil` while `source` keeps them inspectable.
- Typed authority-record views: `CatalogRecord.authorityRecord` projects `authority` records into `CatalogAuthorityRecord` with an open `CatalogAuthorityType` code for the five captured categories, heading, preferred flag, birth and death dates as source components, notes, and exact NAID references for broader, narrower, related, jurisdiction, and personal or organizational terms. Description records and unknown record types project `nil` while still decoding.
- Typed contribution views: `CatalogRecord.comments`, `.tags`, and `.transcriptions` project each top-level contribution array into `CatalogContribution` values in source order, duplicates included, with source timestamps as strings, the machine-generation flag as declared, raw contributors, and an open contributor-source code. `contributionMetadata` exposes the three metadata arrays separately without joining them to contributions. OCR, community transcription, and machine-generated text stay labeled separately; none is certified original text.
- Bulk directory discovery: `BulkDirectoryQuery` lists the immediate children of `authority-records/`, `descriptions/collections/`, and `descriptions/record-groups/` with a slash delimiter, and `BulkDirectoryPage` decodes each delimited listing with exact echoed continuation, scope and nesting validation, and duplicates kept as listed. `CatalogBulkClient.directory(matching:)`, `directoryPages(matching:)`, and `partitions(matching:)` share the manifest pagination rules: lazy independent iterators, bounded page receipts, cancellation, and repeated-token detection. Zero-byte directory marker objects are never yielded as partitions. A discovered prefix proves storage membership only at listing time and is never a parsed record group number or National Archives Identifier.
- Conditional shard refresh: `ShardCondition` carries exactly one `If-Match` or `If-None-Match` entity tag with its exact text preserved. `CatalogBulkClient.refresh(_:condition:to:)`, `value(for:to:)`, and `send(_:to:)` return `ShardRefreshResult.downloaded` with a complete new file, or `.notModified` with the 304 retrieval headers and no file created. A 412 and every other status surface as the transport status with body and headers intact; nothing is retried, and an existing destination is refused before any request. `BulkObjectChange.compare(previous:current:)` compares saved and current listing hints by key, ETag, size, and last-modified; unchanged hints mean no observed metadata change, not byte identity.
- Seventeen attributed official captures (three manifest pages, five directory listings, two description shards, the first shard of each of the five authority categories, a conditional 412 response body, and the headers of a conditional 304 response, which has no body) with attributed URLs, conditional request headers, timestamps, status, headers, byte counts, and SHA-256; historical 1816/1817 and FDR examples; typed failures; two DocC catalogs; and an offline command-line demo.

The public swifty-networking 1.3.1 tag was verified before setting the dependency floor. Its custom page decoder and streamed response receipt are used directly. XML support is source-specific and does not assume networking-package XML parsing. The trait-on lockfile records the portable dependency superset.

## October 4 durable resume local qualification

Begin/resume/discard now execute for bulk JSONL/ZIP representations and original media.
The owner approved SDK-only swift-system 1.8+; resolved 1.8.1 supplies typed no-follow
opening and descriptor identity. Serial validated ranges synchronize partial bytes
before atomic sidecar advancement. Resume verifies SHA-256 and ownership before
truncating crash tails, reloads newer matching sidecars, and refuses concurrent writers,
replaced files and existing destinations. A complete local prefix can publish without
HTTP. Publication is a no-overwrite hard link on the same filesystem. Explicit discard
removes only the bound partial and sidecar, retaining the destination, private directory
and unrelated files. Parent directories must remain stable and caller-controlled;
advisory locks coordinate SDK writers, not arbitrary external mutation. Failed begin
may leave an owned child for inspection and cleanup. A post-link directory-sync failure
may leave a complete destination despite reporting failure.

- Xcode 27 MCP, generated swift-nara-Package, My Mac macOS 27: 235/235 tests in 30 suites,
  zero failures/skips/expected failures/unrun. Final bundle is
  Test-swift-nara-Package-2026.10.04_17-04-09--0500.xcresult; metadata is in
  plans/p9r2-resume-apple-evidence.json. Subsequent Mac build has zero warnings.
- iPhone 18 Pro simulator build passes; four existing generated-test-product sysroot
  warnings, no simulator test execution claimed.
- Linux swift:6.3-noble, default and HTTPPortable: each 235/235 in 30 suites,
  no compiler warnings; plans/p9r2-resume-linux-final.log. Tests cover complete fixture
  reassembly at all call levels, corrupt/missing/replaced/symlink state, writer conflict,
  cancellation, synthetic crash tails, injected checkpoint disk-full before and after
  sidecar advancement, invalid responses, destination races and local-only completion.
  No hardware power-loss test or physically-full-disk test is claimed.
- Source gate 15 checks and self-test 59 planted arms pass; strict formatting includes
  both demos. Logs plans/p9r2-resume-source-final.log and
  plans/p9r2-resume-self-tests-final.log. Fresh local review checked ownership boundaries,
  durable update order, checked offsets, bounded hashing, typed failure progress,
  publication/discard behavior, model dependency isolation and all call forms.
- Four DocC catalogs convert models first with warnings as errors, merge and static
  hosting conversion pass in plans/p9r2-resume-docc-final. The first conversion failed
  because CSystem headers were absent from symbol extraction search paths; the script
  now uses the resolved Xcode checkout and supports an explicit header-path override.
- Both Linux Release demos pass, including labeled synthetic retained-state recovery
  (four bytes retained, eight published, explicit discard) alongside existing captures.
  Logs plans/p9r2-resume-demo-bulk.log and plans/p9r2-resume-demo-media.log.

Xcode temporarily disconnected; filesystem editing was used while MCP returned Transport
closed. Reconnection produced the designated final result. Earlier 231-test and mixed
in-flight Linux checks are superseded. A newly added cancellation test initially failed
to compile due to erased catch type; explicit typed matching fixed it before these runs.
No source fixture or live Catalog content was added. All 23 portable pins remain unchanged;
only the direct-dependency manifest hash changes, while unrelated worktree pin removals
are preserved with the newly direct swift-system pin. Android, current hosted CI/Pages,
publication and release remain open. ZIP acquisition/reading and transient Catalog are
not accepted by this resume qualification. Historical OFR remains owner-deferred.

## October 4 checkpoint foundation qualification (historical slice)

Versioned `BulkDownloadCheckpoint` and `DigitalObjectDownloadCheckpoint` values,
validation-preserving Codable range references, and SDK-only bounded SHA-256 hashing
are implemented. Local checkpoint fixtures are synthetic. The approved swift-crypto
floor is 5.0.0, matching the existing portable pin and this package's tools 6.2 floor.
No models target imports Crypto or depends on a third-party product.

At that foundation boundary, begin/resume/discard execution, exclusive file ownership,
durable sidecar updates, crash recovery and final publication were not qualified by
those tests. The later lifecycle evidence below supersedes that implementation status.
ZIP acquisition/reading and transient Catalog operations remain pending.

Xcode 27 MCP on macOS 27 passes 211 tests in 28 suites with zero failed, skipped,
expected-failure or unrun tests. The designated generated scheme is swift-nara-Package;
the final result is `Test-swift-nara-Package-2026.10.04_16-13-26--0500.xcresult`, recorded
in `plans/p9r2-checkpoint-apple-evidence.json`. Linux default and HTTPPortable pass all
211 tests; both modes additionally pass the four final checkpoint URL-validation tests.
The final simulator build passes with four existing generated-test-product sysroot
linker warnings; it is not simulator test execution. Source checks pass 15 gates and
59 planted arms, including new Crypto/SystemPackage model-boundary cases. The final
Mac build has zero warnings. Four DocC catalogs convert with warnings as errors,
models first, in `plans/p9r2-checkpoint-docc-final`; the conversion exited successfully.
Both Linux Release demos pass with unchanged recorded responses, including their 32-byte
range examples. Their logs are `plans/p9r2-checkpoint-demo-bulk.log` and
`plans/p9r2-checkpoint-demo-media.log`. The verified portable lockfile keeps all 23
existing pins; only its manifest hash changes in the commit. The owner's separate
worktree pin removals are retained, adjusted only for the approved Crypto/ASN1 graph.

The first Apple build after dependency resolution needed a retry because its project
model changed. Two later test attempts returned incomplete bundles and are excluded;
a fresh workspace connection and explicit generated-scheme check produced the designated
211-test pass. Trial 4.5.2 results are superseded by 5.0.0 qualification. Exact Linux logs:
`plans/p9r2-checkpoint-linux-final.log` and
`plans/p9r2-checkpoint-linux-path-final.log`. Android and current hosted/Pages/release
qualification remain open. No remote delivery or sibling edit was performed.

## October 4 local byte-range qualification

Both service pairs now expose a single explicit closed range through everyday, request
and endpoint calls. Strong ETags, known total lengths, optional meaningful bulk version
pins, strict Content-Range and byte-count validation, bounded temporary files and distinct
partial receipts are implemented. Bulk ranges support JSONL and ZIP keys; media ranges
support original objects on both observed prefixes. Existing complete downloads retain
their whole-file contract. At this earlier range boundary, resume, full archive acquisition and ZIP ingestion
were pending implementation.

At the working revision based on `14d401d`, Xcode 27 MCP on macOS 27 and Linux
`swift:6.3-noble` default/HTTPPortable each pass 203 tests in 24 suites, with no failures,
skips or unrun tests. Mac and Linux builds have no compiler warnings. The iOS 27 simulator
build passes with four generated-test-product incompatible-sysroot linker warnings;
no simulator test execution is claimed for this slice. Source checks pass 15 gates and
55 planted arms, including strict formatting. Four DocC catalogs convert with warnings
as errors, and both Linux Release demos replay their additional 32-byte range example.
Twelve new range evidence files match their attributed byte counts and SHA-256 values.

URLSession and HTTPPortable were also exercised against a local synthetic server through
Xcode MCP. Identity bytes and representation headers are preserved; gzip remains labeled
when transparently decompressed. The two SDKs reject the encoded URLSession response.
HTTPPortable was exercised with decompression disabled and enabled. These observations
are on macOS; Linux SDK execution is recorded separately. The initial Xcode and Docker
stalls were recovered, and the initial test compilation failures were fixed before the
passing runs. Evidence: `plans/p9r1-apple-evidence.json`, `plans/p9r1-linux-second.log`,
`plans/p9r1-source-final.log`, `plans/p9r1-self-tests-final.log`, `plans/p9r1-docc-final.log`,
and `plans/p9r1-demo-*.log`.

Historical OFR disposition/codification work is owner-deferred from this repository task.
The owner approved SDK-only swift-crypto and swift-system; the later lifecycle evidence
supersedes the earlier checkpoint-only status. Archive-reader
selection and live Catalog credentials/fixture policy remain separate gates. Android,
current hosted CI, Pages and release remain unqualified; the phase is not fully qualified
across all required platforms. No sibling or remote change was made, and the entry
lockfile edit is preserved.

## October 4 local IIIF derivative qualification

Full-image default-quality JPEG requests now support positive width, height, fit and
server maximum. Requests require explicit validated information, refuse unsupported
profiles/features and exceeded dimensions/limits, and perform no implicit information
or original fetch. A separate derivative receipt retains the original reference,
information identity, requested size and actual HTTP/file evidence. MIME type, when
present, must be JPEG; a chunk-aware start-signature check does not claim full decoding.

At the working revision based on `ddbd1a3`, Xcode 27 MCP on macOS 27 and Linux
default/HTTPPortable each pass 183 tests in 20 suites, with no failures, skips or unrun
tests. Mac and Linux builds have no compiler warnings. The iOS 27 simulator build
passes; it reports two generated-test-product incompatible-sysroot linker warnings.
There is no completed simulator test result for this slice. Source checks pass 15
gates and 55 planted self-test arms, including strict formatting. Four DocC catalogs
convert with warnings as errors. The Linux Release demo replays three responses:
65,981 original bytes, 832 information bytes and 6,031 derivative bytes.
The captured derivative independently reports 200 by 253 pixels; response dimensions
are not asserted by the runtime transfer receipt. Evidence: `plans/p5i2-*.log` and
`plans/p5i2-apple-tests.txt`.

Android, current hosted CI, Pages publication and release remain unqualified.
No sibling repository or remote state was changed; the entry lockfile edit is preserved.

## October 4 local IIIF information qualification

The media pair now retrieves bounded version-3 image information for both supported
source prefixes. It validates service identity, type, protocol and dimensions, retains
raw JSON and HTTP evidence, and never fetches linked contexts or services. The offline
media demo now replays the original JPEG and its information document.

At the working revision based on `5cdce43`, all 175 tests in 18 suites pass through
Xcode 27 MCP on My Mac and in Linux default and HTTPPortable configurations.
The iOS simulator attempt timed out after 300 seconds with an incomplete result
bundle; it supplies no executed-test evidence. Reopening only this package workspace
and using My Mac produced the complete passing result. No test failed, skipped or
remained unrun in that completed run. Linux has no compiler warnings. The earlier
simulator build passed with four generated-test-product sysroot linker warnings.
Source validation passes 15 checks and 55 planted self-test arms; strict formatting,
four DocC conversions with warnings as errors, and the Linux Release media demo pass.
Evidence: `plans/p5i1-*.log` and `plans/p5i1-apple-tests.txt`.

The three newly attributed captures are two information documents and one small FDR
JPEG derivative reserved for download validation. No Fold3 media or live Catalog API
content was saved. Android, current hosted CI, Pages and release remain unqualified.

## October 4 local media qualification

The independent `SwiftNARADigitalObjects` SDK implements original-file downloads through
everyday methods, request factories and typed endpoints. Explicit object and diagnostic
byte limits, no-redirect transport, whole-body validation, bounded substituted-page evidence,
cancellation cleanup and new-file publication are covered by nine SDK tests. Real HTML is
accepted, missing media type remains nil, and observed CDN error markers are not an
authenticity guarantee. No new provider body was captured.

At the working revision based on `264ec4f`, Xcode 27 MCP passed 168 tests in 16 suites on
iPhone 18 Pro / iOS 27; Linux default and HTTPPortable passed the same 168 tests with no
compiler warnings. The first Apple attempt returned an incomplete result bundle and is
not counted as executed-test evidence; its retry passed with none skipped or unrun.
The Linux Release media demo replays exactly 65,981 JPEG bytes with no live request.
Xcode emits three incompatible macOS/iOS sysroot linker warnings for test products.
Source gates pass 15 checks and 55 planted self-test arms, now checking both models
products for import boundaries and absent subjects. Four DocC catalogs convert with
warnings treated as errors, models before each SDK. Evidence: `plans/p5d-*.log`.

Android, hosted CI, Pages publication and release remain unqualified for this revision.
Local workflow changes include the new media products and offline demo; they do not
represent executed hosted jobs.

## October 4 local metadata qualification

Six additive digital-object projections are implemented, with original fixture bytes unchanged:
complete OCR, declared accuracy, description, designator, partner text, and thumbnail URL.
The published schema backs accuracy, partner text, and thumbnails; retained bulk captures
do not contain those three fields. Existing media references, requests and receipts also
compile, but there is still no media SDK in this revision.

The metadata change based on `9127f8a` passed all 159 tests in 15 suites through Xcode 27
MCP on iPhone 18 Pro / iOS 27 and in both Linux default and HTTPPortable configurations
using `swift:6.3-noble`. Source verification passes all 15 checks and 47 planted self-test
arms; strict formatting passes. Both bulk DocC catalogs convert with warnings treated as
errors, models first, and the Linux Release offline demo passes. Xcode reports two existing
incompatible macOS/iOS sysroot linker warnings. Evidence is retained in ignored
`plans/p5m-*.log` files and the execution ledger.

No Swift Android SDK, adb, or emulator is installed locally. Android, hosted tests and
Pages have not been requalified for this change. The earlier hosted results below are
historical evidence, and no release is published. The entry lockfile change is preserved.

## Local qualification

Reverified September 26, 2026 UTC on the working tree committed as the direct child of `9d594c9`, the commit that adds conditional shard refresh and records this table. Earlier qualification logs and documentation archives are retained in the ignored `plans/` directory.

| Gate | Evidence and remaining limit |
| --- | --- |
| Source conventions | All 15 checks pass; 47 planted self-test cases pass. Recorded JSONL prose is excluded only inside the fixture directory, with negative coverage for authored JSONL elsewhere. |
| Strict formatting | Sources, Tests, both package manifests, and demo source pass. |
| Linux default and HTTPPortable | 129 tests in 12 suites pass in each configuration, with no compiler warnings, using `bash Scripts/linux-test.sh` and `swift:6.3-noble`. |
| Apple via Xcode MCP | The generated `swift-nara-Package` scheme builds for testing and all 129 tests in 12 suites pass on iPhone 18 Pro / iOS 27 using Xcode 27. No tests fail, skip, or remain unrun. The local build still emits incompatible macOS/iOS sysroot linker warnings for generated test products. Apple Release demo verification is hosted, as recorded below. |
| Android | No installed Swift Android SDK, adb, or emulator was available locally. Android remains hosted-only; the hosted emulator qualification below predates the archival-description, authority-record, and contribution views, bulk directory discovery, and conditional shard refresh, and has not been rerun for this revision. |
| DocC | `Scripts/build-docs.sh` passes using Apple iOS simulator modules built through Xcode MCP. Both catalogs convert with warnings treated as errors, models first; merged archive and static site generation pass, including Apple-only URLSession symbols. |
| Release demo | The standalone SwiftPM command-line example builds and runs in the Linux container, listing the five authority partitions from one recorded directory page, then reading two manifest pages, seven shard records, and one person authority shard. It prints each record's typed level, production date, ancestor count, access restriction, digital-object declaration, and transcription count by machine-generation flag, then the first person authority's heading and type. It then replays a recorded 304 for the FDR shard, printing its ETag while the saved file stays untouched, and replays the recorded 200 into a second new destination, from six recorded responses in all. |

## Hosted qualification

Verified September 26, 2026 UTC at commit `9b0e9974888e955fe6674ed63340cf5b128c3dda`. [CI run 36249214603](https://github.com/KalebCooper/swift-nara/actions/runs/36249214603) and [Docs run 36249214583](https://github.com/KalebCooper/swift-nara/actions/runs/36249214583) pass with all seven jobs successful and none skipped. Pages deployment initially failed because the repository had no Pages configuration; after enabling Actions-based Pages, the failed deployment passed on retry. This hosted qualification predates the archival-description, authority-record, and contribution views, bulk directory discovery, and conditional shard refresh; those additions are qualified locally only, as recorded above, until the retained hosted lanes run on a later revision.

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

The earlier hosted CI and documentation runs are historical evidence. Current changes require new hosted runs. Job durations above provide a measured green main baseline for future timeout adjustments. No release is published; tagging and releases require separate approval.

The later full historical inventory is coordinated with GovInfo document work. Independent NARA manifest and shard slices do not depend on that inventory. This implementation does not claim all-history completeness, current-administration coverage, stable snapshots, OCR accuracy, or unrestricted rights. The separate Catalog HTTP API remains excluded from persistent ingestion. Application inclusion policy, cross-provider identity resolution, and release approval remain outside this slice.
