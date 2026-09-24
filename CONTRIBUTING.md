# Contributing

Run `bash Scripts/verify.sh` and `bash Scripts/verify.sh --self-test` before committing. Strict formatting covers the package manifests, Sources, Tests, and the example. Source verification retains its absent-module guard and tests its own failure paths.

Implement complete source slices: portable models and endpoints, their independent client, attributed recorded fixtures, Swift Testing, consumer examples, DocC, and an accurate README/changelog. Preserve source identifiers, unknown fields, nulls, original dates, restrictions, and opaque continuation. Models have no networking dependencies. Never replace recorded bodies with normalized or reconstructed data.

Use Swift 6, shared strict settings, and alphabetical declarations within logical groups. Use Xcode MCP and the generated package scheme for supported Apple operations. Linux verification runs through `bash Scripts/linux-test.sh`, exercising both default and HTTPPortable configurations. `bash Scripts/demo-linux.sh` builds and executes the recorded-response example in Release.

Before delivery, complete the Apple, Linux, Android, documentation, and demo gates listed in [implementation readiness](IMPLEMENTATION_READINESS.md). Keep incomplete gates explicit; a Linux pass does not qualify Apple or Android. Retained platform and documentation CI remain disabled until qualification is complete. CI timeouts are provisional until measured green hosted runs exist. Use focused Conventional Commits; publishing requires owner authorization.
