#!/usr/bin/env bash
#
# Runs the package's tests on Linux, in the swift:6.3-noble container image, so the claim that the
# package builds off Apple platforms is checked before a push instead of after one. Anything
# Darwin-only is expected to compile out; a failure here is a real portability regression.
#
# With no trait list given, the suite runs twice. First with `HTTPPortable` enabled, which forwards
# the trait to swifty-networking and builds its AsyncHTTPClient transport and the SwiftNIO stack
# beneath it. Then under the package's default trait set, which enables none, proving what a consumer
# who asks for no trait gets.
#
# Usage: ./Scripts/linux-test.sh [additional swiftpm arguments]
#   e.g. ./Scripts/linux-test.sh --filter SwiftNARACatalogBulkModelsTests
#
# Set SWIFT_NARA_TRAITS to run once under that trait list instead:
#   e.g. SWIFT_NARA_TRAITS=HTTPPortable ./Scripts/linux-test.sh
# Set it to the empty string for a single run under the default trait set.

set -euo pipefail

# Source-dependent validation is unavailable until both real service modules exist.
readiness_root="${VERIFY_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
if true; then
  for module in SwiftNARACatalogBulk SwiftNARACatalogBulkModels; do
    if [ ! -d "$readiness_root/Sources/$module" ] || ! find "$readiness_root/Sources/$module" -name '*.swift' -type f | grep -q .; then
      echo "Not ready: $module source is not implemented; see IMPLEMENTATION_READINESS.md." >&2
      exit 1
    fi
  done
fi

# Pinned: a local pass is only evidence about a CI lane if it is the same toolchain.
readonly IMAGE="swift:6.3-noble"

# Build products live in a named volume rather than in the repo, for two reasons: Linux object files
# must not share a scratch directory with the host's macOS build, and a volume survives the container
# so repeat runs are incremental instead of cold. Each trait set gets a directory of its own inside
# it, because the same manifest under another trait set is a different build graph.
readonly SCRATCH_VOLUME="swift-nara-linux-build"

readonly REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

if ! docker info >/dev/null 2>&1; then
  echo "error: docker is not available. Start Docker Desktop and try again." >&2
  exit 1
fi

docker volume create "$SCRATCH_VOLUME" >/dev/null

# $1: trait list, empty for the default trait set; the rest: additional swiftpm arguments.
run_suite() {
  local traits="$1"
  shift
  local scratch="/scratch/default"
  local traits_argument=()
  if [ -n "$traits" ]; then
    scratch="/scratch/traits-${traits//,/-}"
    traits_argument=(--traits "$traits")
  fi
  echo "==> swift-nara on Linux, traits: ${traits:-default}"
  # `${array[@]+...}` guards the expansion: under `set -u` the bash macOS ships rejects an empty array.
  docker run --rm \
    --volume "$REPO_ROOT:/workspace" \
    --volume "$SCRATCH_VOLUME:/scratch" \
    --workdir /workspace \
    "$IMAGE" \
    swift test --scratch-path "$scratch" \
    ${traits_argument[@]+"${traits_argument[@]}"} "$@"
}

# Unset means both runs; explicitly empty means one run under the default trait set, so `+` rather
# than `:+` is the test that tells the two apart.
if [ -n "${SWIFT_NARA_TRAITS+set}" ]; then
  run_suite "$SWIFT_NARA_TRAITS" "$@"
  exit 0
fi

run_suite "HTTPPortable" "$@"

# A run under the default trait set resolves fewer packages and prunes `Package.resolved` to match.
# The tracked file is the superset the trait-enabled run writes, so it is put back afterward.
readonly RESOLVED="$REPO_ROOT/Package.resolved"
resolved_snapshot=""
if [ -f "$RESOLVED" ]; then
  resolved_snapshot="$(mktemp "${TMPDIR:-/tmp}/swift-nara-resolved.XXXXXX")"
  cp "$RESOLVED" "$resolved_snapshot"
  trap 'cp "$resolved_snapshot" "$RESOLVED"; rm -f "$resolved_snapshot"' EXIT
fi

run_suite "" "$@"
