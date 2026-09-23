#!/usr/bin/env bash
# Explicit scaffold mode checks infrastructure only. Default mode requires real source.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
case "${1:-}" in
  --scaffold) python3 "$ROOT/Scripts/verify-scaffold.py" ;;
  --self-test)
    python3 "$ROOT/Scripts/verify-scaffold.py" --self-test
    bash "$ROOT/Scripts/verify-source.sh" --self-test
    ;;
  "") bash "$ROOT/Scripts/verify-source.sh" ;;
  *) echo "Usage: $0 [--scaffold|--self-test]" >&2; exit 2 ;;
esac
