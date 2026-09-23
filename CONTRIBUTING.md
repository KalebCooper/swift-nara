# Contributing

The repository currently contains infrastructure only. Run `bash Scripts/verify.sh --scaffold` and `bash Scripts/verify.sh --self-test` before committing infrastructure changes. `bash Scripts/verify.sh` is the full source gate and intentionally fails in this state.

Implement a complete service slice only after the shared networking prerequisite is verified. Add portable models/endpoints and their independent client together with recorded fixtures, Swift Testing suites, consumer examples, DocC catalogs, and an honest README/changelog update. Preserve unknown values, nulls, identifiers, dates, and provider continuation links.

Use Swift 6, the manifest's shared strict settings, alphabetical declarations within logical groups, and strict formatting. Models have no networking dependencies. Tests use recorded provider data rather than live requests. Use Xcode MCP tools for Apple project operations and generated package schemes.

Before publishing source, complete the Apple, Linux default/portable, Android, documentation, and demo gates listed in [implementation readiness](IMPLEMENTATION_READINESS.md). CI timeouts are provisional until measured green runs exist. Use focused Conventional Commits; publishing requires owner authorization.
