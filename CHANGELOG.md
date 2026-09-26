# Changelog

All notable changes are documented here, following Keep a Changelog and Semantic Versioning.

## Unreleased

### Added

- Independent `SwiftNARACatalogBulkModels` and `SwiftNARACatalogBulk` products using verified swifty-networking 1.3.1 APIs.
- Portable bounded S3 XML decoding, typed manifest requests/endpoints, and lazy page/object traversal with opaque token validation and exact response receipts.
- Streamed JSONL downloads with complete-file receipts, byte bounds, cleanup on failure, and bounded independent local line iteration.
- Open source records preserving NAIDs, hierarchy, digital objects, OCR/contributions, unknown/null fields, metadata-only descriptions, and restrictions.
- Typed archival-description views (`CatalogDescription`, `CatalogAncestor`, `CatalogDescriptionLevel`, `CatalogDate`, `CatalogRestriction`, `CatalogRestrictionStatus`) and `CatalogRecord.archivalDescription`, projecting existing envelopes without changing raw source data.
- Typed authority-record views (`CatalogAuthorityRecord`, `CatalogAuthorityType`, `CatalogNAIDReference`) and `CatalogRecord.authorityRecord`, and typed contribution views (`CatalogContribution`, `CatalogContributionMetadata`, `CatalogContributionSource`, `CatalogContributionTarget`) with `CatalogRecord.comments`, `.tags`, `.transcriptions`, and `.contributionMetadata`, projecting existing envelopes without changing raw source data.
- Attributed original manifest, RG11, and FDR fixtures, deterministic Swift Testing coverage, two DocC catalogs, and an offline command-line demo.
- Provider evidence and explicit qualification status; source validation retains absent-subject and planted-violation coverage.

### Fixed

- Enable Apple, Android, Linux, strict formatting, and DocC build checks on pushes and pull requests.
- Publish the DocC site after successful documentation builds on main.
