#!/usr/bin/env bash
# Build the offline example for Release and run it against unchanged recorded responses.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
docker run --rm --volume "$root:/workspace" --volume swift-nara-linux-build:/scratch \
  --workdir /workspace/Examples/SwiftNARACatalogBulkDemo swift:6.3-noble \
  bash -lc 'swift build -c release --scratch-path /scratch/demo && /scratch/demo/release/SwiftNARACatalogBulkDemo /workspace/Sources/SwiftNARACatalogBulkTestSupport/Fixtures'
