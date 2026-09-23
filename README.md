# swift-nara

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

Swift package infrastructure for National Archives Catalog bulk data.

## Status

Infrastructure only. No government API, library products, source targets, fixtures, or tests are implemented. The package is not ready for application use and has no release or remote repository configured.

Future coverage is official bulk manifest discovery, streaming JSONL records, archival descriptions, and digital-object links. Bulk snapshots do not guarantee current or complete historical coverage. Preserve item restrictions and rights; the package license grants no rights to archival content. The separate Catalog API is excluded from persistent ingestion. Coverage, freshness, ordering, and representation availability must be verified when implemented.

## Usage

Run `bash Scripts/verify.sh --scaffold` to validate infrastructure. The default verification command deliberately fails until service source exists. See [implementation readiness](IMPLEMENTATION_READINESS.md) for deferred gates.

## Example

No API example is available because no API is implemented.

## Products

| Product | Status |
| --- | --- |
| None | Products are added only with working service source. |

## Requirements

The manifest declares Swift tools 6.2, Swift 6 language mode, and iOS, macOS, tvOS, visionOS, and watchOS 26. Infrastructure verification needs Bash, Python 3, Git, and Swift with swift-format. No Apple, Linux, or Android library compatibility has been established yet.

## Installation

No installable library or published version exists yet. Dependency pins and the portable transport trait will be added with the first implemented slice after the shared networking prerequisite is complete.

## License

MIT. See [LICENSE](LICENSE). The package license does not grant rights to upstream content.
