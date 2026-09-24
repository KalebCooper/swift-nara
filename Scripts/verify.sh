#!/usr/bin/env bash
# Source verification retains absent-subject protection and planted-violation self-tests.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
case "${1:-}" in
  ""|--self-test) bash "$ROOT/Scripts/verify-source.sh" "$@" ;;
  *) echo "Usage: $0 [--self-test]" >&2; exit 2 ;;
esac
