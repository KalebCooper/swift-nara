#!/usr/bin/env bash
# Build and run the offline original-media example.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
docker run --rm --volume "$root:/workspace" --volume swift-nara-linux-build:/scratch \
  --workdir /workspace/Examples/SwiftNARADigitalObjectsDemo swift:6.3-noble \
  bash -lc 'swift build -c release --scratch-path /scratch/media-demo && /scratch/media-demo/release/SwiftNARADigitalObjectsDemo /workspace/Sources/SwiftNARADigitalObjectsTestSupport/Fixtures'

