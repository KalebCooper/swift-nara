#!/usr/bin/env bash
# Convert only this package's products from already-built iOS simulator modules.
# Dependencies must compile, but their documentation is not part of this site.
set -euo pipefail

# Source-dependent validation is unavailable until both real service modules exist.
readiness_root="${VERIFY_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
if true; then
  for module in SwiftNARACatalogBulk SwiftNARACatalogBulkModels SwiftNARADigitalObjects SwiftNARADigitalObjectsModels; do
    if [ ! -d "$readiness_root/Sources/$module" ] || ! find "$readiness_root/Sources/$module" -name '*.swift' -type f | grep -q .; then
      echo "Not ready: $module source is not implemented; see IMPLEMENTATION_READINESS.md." >&2
      exit 1
    fi
  done
fi

modules="${1:?Usage: bash Scripts/build-docs.sh MODULES_DIRECTORY OUTPUT_DIRECTORY [TARGET]}"
output="${2:?Supply a new output directory}"
sdk="$(xcrun --sdk iphonesimulator --show-sdk-path)"
target="${3:-$(uname -m)-apple-ios26.0-simulator}"
# Xcode stores the C module map in its resolved dependency checkout, not Products.
system_headers="${SWIFT_NARA_SYSTEM_HEADERS:-$modules/../../../SourcePackages/checkouts/swift-system/Sources/CSystem/include}"
if [[ ! -f "$system_headers/module.modulemap" ]]; then
  echo "Missing swift-system C module headers: $system_headers. Set SWIFT_NARA_SYSTEM_HEADERS for a custom checkout." >&2
  exit 1
fi

if [[ -e "$output" ]]; then
  echo "Output already exists: $output. Supply a new directory." >&2
  exit 1
fi
mkdir -p "$output/module-cache"
archives=()
# Models precede their matching SDK so cross-product symbol references resolve.
for service in CatalogBulk DigitalObjects; do
  for suffix in Models ""; do
    module="SwiftNARA$service$suffix"
    symbols="$output/$module-symbols"
    archive="$output/$module.doccarchive"
    mkdir -p "$symbols"
    xcrun swift-symbolgraph-extract -module-name "$module" \
      -target "$target" -sdk "$sdk" -I "$modules" -I "$system_headers" \
      -module-cache-path "$output/module-cache" \
      -output-dir "$symbols" -minimum-access-level public
    dependency=()
    if [[ -z "$suffix" ]]; then
      dependency=(--dependency "$output/SwiftNARA${service}Models.doccarchive")
    fi
    xcrun docc convert "Sources/$module/$module.docc" \
      --additional-symbol-graph-dir "$symbols" --output-dir "$archive" \
      --enable-experimental-external-link-support --warnings-as-errors \
      ${dependency[@]+"${dependency[@]}"}
    archives+=("$archive")
  done
done
xcrun docc merge "${archives[@]}" \
  --synthesized-landing-page-name swift-nara --synthesized-landing-page-kind Package \
  --output-path "$output/merged.doccarchive"
xcrun docc process-archive transform-for-static-hosting "$output/merged.doccarchive" \
  --output-path "$output/site" --hosting-base-path swift-nara

# The archive's app shell has no root route under the Pages subpath.
cat > "$output/site/index.html" <<'HTML'
<!DOCTYPE html>
<html lang="en">
  <head>
    <meta charset="utf-8">
    <meta http-equiv="refresh" content="0; url=documentation/">
    <link rel="canonical" href="https://kalebcooper.github.io/swift-nara/documentation/">
    <title>swift-nara</title>
  </head>
  <body>
    <p>Redirecting to the <a href="documentation/">swift-nara documentation</a>.</p>
  </body>
</html>
HTML
