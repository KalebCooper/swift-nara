#!/usr/bin/env bash
# The pre-commit gate. Every invariant here is one the compiler cannot see and the test suite cannot
# fail on, so a grep is the only guard it has.
#
# Usage:
#   Scripts/verify.sh              run every check against this tree; exit 0 iff all pass
#   Scripts/verify.sh --self-test  prove every check still discriminates: each one is run against a
#                                  synthesized clean tree (must pass) and a tree with one planted
#                                  violation (must fail), outside the repository
#
# Two kinds of check, and each declares which kind it is:
#   - A prohibition greps for a forbidden construct. An empty match set is the passing state, so a
#     live run proves nothing about whether the grep still works; only --self-test does.
#   - A derivation builds a set from the tree and compares it to what the tree promises. An empty
#     derived set FAILS, because a derivation that finds nothing has lost its subject.
# A prohibition scoped to one directory first asserts that the directory holds Swift source, so a
# renamed or emptied target fails loudly instead of passing a check about nothing.

set -u

# Source-dependent validation is unavailable until both real service modules exist.
readiness_root="${VERIFY_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
if [ "${1:-}" != "--self-test" ]; then
  for module in SwiftNARACatalogBulk SwiftNARACatalogBulkModels; do
    if [ ! -d "$readiness_root/Sources/$module" ] || ! find "$readiness_root/Sources/$module" -name '*.swift' -type f | grep -q .; then
      echo "Not ready: $module source is not implemented; see IMPLEMENTATION_READINESS.md." >&2
      exit 1
    fi
  done
fi

ROOT="${VERIFY_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
FAILURES=0

pass() { printf '[PASS] %s\n' "$1"; }
fail() { printf '[FAIL] %s\n' "$1"; FAILURES=$((FAILURES + 1)); }

# Lines of Swift source with comment-only lines removed, so a doc comment may name a banned
# construct while explaining why it is banned.
code_lines() {
  # $@: files
  grep -nHvE '^\s*//' "$@" 2>/dev/null
}

swift_files() {
  # $1: directory under ROOT
  find "$ROOT/$1" -name '*.swift' -type f 2>/dev/null | sort
}

# ---------------------------------------------------------------------------------------------------
# Checks. Each is a function that calls pass or fail exactly once.
# ---------------------------------------------------------------------------------------------------

# Prohibition. swift-format's NeverForceUnwrap and NeverUseForceTry cover `!` and `try!`; `as!` has no
# lint rule, so it is grepped here alongside `try!` for one place to read the rule.
check_force_ops() {
  local name="no try! or as! in Sources"
  local hits
  hits=$(code_lines $(swift_files Sources) | grep -E '\btry!|\bas!' || true)
  if [ -z "$hits" ]; then pass "$name"; else fail "$name"; printf '%s\n' "$hits"; fi
}

# Prohibition. SwiftNARACatalogBulkModels builds on every platform the package supports, so it imports Foundation
# only under the `#else` of a `#if canImport(FoundationEssentials)`.
check_models_foundation_import() {
  local name="every import Foundation in Sources/SwiftNARACatalogBulkModels sits under #else"
  local files hits
  files=$(swift_files Sources/SwiftNARACatalogBulkModels)
  if [ -z "$files" ]; then fail "$name (Sources/SwiftNARACatalogBulkModels holds no Swift file; the check has lost its subject)"; return; fi
  # awk rather than grep -B1: a file whose first line is the import has no preceding line for -B1 to
  # show, and the filter would drop the hit.
  hits=$(awk 'FNR == 1 { prev = "" } /^import Foundation$/ && prev != "#else" { print FILENAME ":" FNR ": " $0 } { prev = $0 }' $files 2>/dev/null || true)
  if [ -z "$hits" ]; then pass "$name"; else fail "$name"; printf '%s\n' "$hits"; fi
}

# Prohibition. SwiftNARACatalogBulkModels is usable on any data layer, so it reaches for no networking stack: not
# swifty-networking or the HTTP types beneath it, not the SwiftNIO stack, not URLSession, and not the
# SDK built on top of it. Every spelling of an import counts (an attribute, an access level, a
# declaration kind), so an import cannot hide behind one; `\b` keeps `SwiftNARACatalogBulkModels` itself out of
# the `SwiftNARACatalogBulk` match.
check_models_import_boundary() {
  local name="no swifty-networking, transport, or SDK import in Sources/SwiftNARACatalogBulkModels"
  local files hits
  files=$(swift_files Sources/SwiftNARACatalogBulkModels)
  if [ -z "$files" ]; then fail "$name (Sources/SwiftNARACatalogBulkModels holds no Swift file; the check has lost its subject)"; return; fi
  hits=$(code_lines $files | grep -E ':[0-9]+:[[:space:]]*(@[A-Za-z_]+(\([^)]*\))?[[:space:]]+)*((public|package|internal|fileprivate|private)[[:space:]]+)?import[[:space:]]+((typealias|struct|class|enum|protocol|let|var|func)[[:space:]]+)?(AsyncHTTPClient|FoundationNetworking|HTTPCore|HTTPPortable|HTTPTesting|HTTPTypes|HTTPTypesFoundation|HTTPURLSession|_?NIO[A-Za-z0-9_]*|SwiftNARACatalogBulk)\b|\bURLSession' || true)
  if [ -z "$hits" ]; then pass "$name"; else fail "$name"; printf '%s\n' "$hits"; fi
}

# Prohibition. Nothing in any target reaches for a UI framework, Combine, Observation, or Dispatch.
check_banned_imports() {
  local name="no banned import in Sources"
  local hits
  hits=$(grep -nHE '^\s*import (AppKit|Combine|Dispatch|Observation|SwiftUI|UIKit)\b' $(swift_files Sources) 2>/dev/null || true)
  if [ -z "$hits" ]; then pass "$name"; else fail "$name"; printf '%s\n' "$hits"; fi
}

# Prohibition. Time is injected; shared state is Synchronization's vocabulary.
check_wall_clock_and_locks() {
  local name="no wall clock, nanosecond sleep, DispatchQueue, NSLock, or OSAllocatedUnfairLock in Sources"
  local hits
  hits=$(code_lines $(swift_files Sources) | grep -E 'Date\(\)|Date\.now|Task\.sleep\(nanoseconds|DispatchQueue|NSLock|OSAllocatedUnfairLock' || true)
  if [ -z "$hits" ]; then pass "$name"; else fail "$name"; printf '%s\n' "$hits"; fi
}

# Prohibition. The package carries no `unsafe`. A first one is a design decision, and it lands with a
# carve-out here naming its file.
check_unsafe() {
  local name="no unsafe in Sources"
  local hits
  hits=$(code_lines $(swift_files Sources) | grep -wE 'unsafe' || true)
  if [ -z "$hits" ]; then pass "$name"; else fail "$name"; printf '%s\n' "$hits"; fi
}

# Derivation. HTTPURLSession exists only on Apple platforms, so every file that imports it compiles
# only under `#if canImport(Darwin)`, and the Linux and Android builds compile it out. The subject is
# derived from the import rather than from a directory, because these files live among the rest of
# the SDK and its tests. Every spelling of the import counts, so an unguarded file cannot hide behind
# an attribute or an access level.
check_darwin_guard() {
  local name="every file that imports HTTPURLSession is wrapped in #if canImport(Darwin)"
  local files missing
  files=$(grep -lE '^\s*(@[A-Za-z_]+\s+)*((public|package|internal|fileprivate|private)\s+)?import ([a-z]+ )?HTTPURLSession\b' $(swift_files Sources) $(swift_files Tests) 2>/dev/null </dev/null | sort)
  if [ -z "$files" ]; then fail "$name (no file imports HTTPURLSession; the check has lost its subject)"; return; fi
  missing=$(grep -L '^#if canImport(Darwin)' $files || true)
  if [ -z "$missing" ]; then pass "$name"; else fail "$name"; printf '%s\n' "$missing"; fi
}

# Prohibition. Comments state constraints in domain terms; provenance belongs in commit messages.
check_coordinates() {
  local name="no plan, phase, task, or turn coordinates in Sources or Tests"
  local hits section
  section=$(printf '\302\247')
  hits=$(grep -nHE "\\bP[0-9]+-T[0-9]+\\b|\\bPh[a]se [0-9]|\\bT[a]sk [0-9]|\\bturn[- ][0-9]+\\b|$section" $(swift_files Sources) $(swift_files Tests) 2>/dev/null || true)
  if [ -z "$hits" ]; then pass "$name"; else fail "$name"; printf '%s\n' "$hits"; fi
}

# Prohibition. No em dashes anywhere written here. A recorded response body is the provider's words
# rather than this repository's, so the scan skips `.json`, the format every recording is saved in.
# The exclusion is by extension rather than by the Fixtures directory because prose this repository
# does write lives there too, such as a README naming what each recording holds, and excluding the
# directory would drop it from the scan with nothing to say so. A recording saved in some other
# format, and this service offers application/cap+xml, trips the check on the day it is added and
# joins the exclusion then, which is the loud failure rather than the silent one.
check_em_dash() {
  local name="no em dash in Sources, Tests, Scripts, .github, Package.swift, .spi.yml, README, CHANGELOG, CONTRIBUTING, recordings aside"
  local hits dash
  dash=$(printf '\342\200\224')
  hits=$(grep -rnH --exclude='*.json' -- "$dash" "$ROOT/Sources" "$ROOT/Tests" "$ROOT/Scripts" "$ROOT/.github" "$ROOT/Package.swift" "$ROOT/.spi.yml" "$ROOT/README.md" "$ROOT/CHANGELOG.md" "$ROOT/CONTRIBUTING.md" 2>/dev/null || true)
  if [ -z "$hits" ]; then pass "$name"; else fail "$name"; printf '%s\n' "$hits"; fi
}

# Prohibition. Testing vocabulary: name the type, never "double", "the driver", or "the seam". The
# em-dash check's scope minus Scripts, Package.swift, and .spi.yml, which carry no prose about tests,
# and its `.json` exclusion for the reason stated there: the provider's own glossary defines seepage
# through seams in a dam abutment and a hurricane's double-eye, and neither one is this repository
# writing about its tests.
check_test_jargon() {
  local name="no test double, driver, or seam jargon in Sources, Tests, .github, README, CHANGELOG, CONTRIBUTING, recordings aside"
  local hits
  hits=$(grep -rnHwiE --exclude='*.json' "test doubles?|doubles|(the|a|second|no) double|the driver|the seam|a seam|seams" "$ROOT/Sources" "$ROOT/Tests" "$ROOT/.github" "$ROOT/README.md" "$ROOT/CHANGELOG.md" "$ROOT/CONTRIBUTING.md" 2>/dev/null || true)
  if [ -z "$hits" ]; then pass "$name"; else fail "$name"; printf '%s\n' "$hits"; fi
}

# Prohibition, with a derivation guarding its subject. Swift Testing only; the derivation asserts a
# test file imports Testing so an empty Tests tree cannot pass.
check_swift_testing_only() {
  local name="Swift Testing only in Tests"
  local files hits testing
  files=$(swift_files Tests)
  testing=$(grep -l '^import Testing$' $files 2>/dev/null | wc -l | tr -d ' ')
  if [ "$testing" -eq 0 ]; then fail "$name (no file imports Testing; the check has lost its subject)"; return; fi
  hits=$(grep -nHE 'import XCTest|XCTestCase|XCTAssert' $files 2>/dev/null || true)
  if [ -z "$hits" ]; then pass "$name"; else fail "$name"; printf '%s\n' "$hits"; fi
}

# Derivation. Every job in every workflow carries a job-level `timeout-minutes`, so a hang fails the
# job instead of sitting for GitHub's six-hour default. The job set is derived from the files and
# must be non-empty. A key is recognized only at the job's own indent: one nested inside a step
# bounds that step, not the job, and leaves the job unbounded. Any two-space key inside `jobs:`
# counts as a job, quoted spellings included, so an unrecognized name fails loudly rather than
# making its job invisible to the scan.
check_job_timeouts() {
  local name="every job in .github/workflows carries a timeout-minutes"
  local files report
  files=$(find "$ROOT/.github/workflows" \( -name '*.yml' -o -name '*.yaml' \) -type f 2>/dev/null | sort)
  if [ -z "$files" ]; then fail "$name (no workflow file found; the check has lost its subject)"; return; fi
  # `jobs:` is the only top-level block whose two-space keys are job names, so the scan tracks which
  # top-level block it is in rather than trusting the indent alone. The name is taken from the whole
  # line rather than the first field, so a quoted name carrying a space stays one name.
  report=$(awk '
    function close_job() {
      if (job != "") { total++; if (!has) print jobfile ": job " job " has no timeout-minutes" }
      job = ""; has = 0
    }
    FNR == 1 { close_job(); in_jobs = 0 }
    /^[^[:space:]#]/ { close_job(); in_jobs = ($0 ~ /^jobs:[[:space:]]*$/); next }
    in_jobs && /^  [^[:space:]#].*:[[:space:]]*$/ {
      close_job(); job = $0; sub(/^  /, "", job); sub(/:[[:space:]]*$/, "", job); jobfile = FILENAME; next
    }
    in_jobs && job != "" && /^    timeout-minutes:[[:space:]]*[0-9]+[[:space:]]*(#.*)?$/ { has = 1; next }
    END { close_job(); if (total == 0) print "NO-JOBS" }
  ' $files 2>/dev/null || true)
  if [ "$report" = "NO-JOBS" ]; then
    fail "$name (no job found in any workflow; the check has lost its subject)"
  elif [ -z "$report" ]; then
    pass "$name"
  else
    fail "$name"; printf '%s\n' "$report"
  fi
}

# Derivation. Every suite under Tests carries the shared time limit, so a test that stops making
# progress fails its suite instead of holding the run open. The suite set is derived from the tree
# and must be non-empty. Four things the scan has to survive. The attribute is read across its whole
# argument list rather than one line, because swift-format wraps a long one onto a second line.
# String contents and any trailing comment are dropped before the constant is looked for, so neither
# a display name nor a comment can stand in for the trait. A suite counts wherever it is written:
# indented inside another suite, or behind another attribute on the same line, because a suite the
# scan failed to recognize would make this check go quiet instead of loud. And a test written at
# file scope belongs to an implicit suite that no attribute can reach, so it would run unbounded no
# matter what the suites carry; it is refused here rather than left to be discovered by a hang.
check_suite_time_limit() {
  local name="every suite in Tests carries the shared time limit"
  local files report
  files=$(swift_files Tests)
  if [ -z "$files" ]; then fail "$name (no test file found; the check has lost its subject)"; return; fi
  report=$(awk '
    # The line reduced to code: string contents dropped, and everything from a trailing comment on.
    # A comment is only a comment outside a string, so the two are tracked in one pass.
    function code(s,   i, c, out, instr, esc) {
      out = ""; instr = 0; esc = 0
      for (i = 1; i <= length(s); i++) {
        c = substr(s, i, 1)
        if (instr) {
          if (esc) esc = 0
          else if (c == "\\") esc = 1
          else if (c == "\"") instr = 0
          continue
        }
        if (c == "\"") { instr = 1; continue }
        if (c == "/" && substr(s, i + 1, 1) == "/") break
        out = out c
      }
      return out
    }
    function balance(s,   i, c, d) {
      d = 0
      for (i = 1; i <= length(s); i++) {
        c = substr(s, i, 1)
        if (c == "(") d++
        else if (c == ")") d--
      }
      return d
    }
    /^[[:space:]]*\/\// { next }
    /^(@[A-Za-z_][A-Za-z0-9_]*(\([^)]*\))?[[:space:]]+)*@Test([[:space:](]|$)/ {
      print FILENAME ":" FNR ": a test at file scope has no suite to bound it"
      next
    }
    /^[[:space:]]*(@[A-Za-z_][A-Za-z0-9_]*(\([^)]*\))?[[:space:]]+)*@Suite([[:space:](]|$)/ {
      total++
      buf = code($0); loc = FILENAME ":" FNR; depth = balance(buf)
      while (depth > 0 && (getline) > 0) {
        chunk = code($0); buf = buf " " chunk; depth += balance(chunk)
      }
      if (index(buf, "suiteTimeLimitMinutes") == 0) print loc ": " buf
      next
    }
    END { if (total == 0) print "NO-SUITES" }
  ' $files 2>/dev/null || true)
  if [ "$report" = "NO-SUITES" ]; then
    fail "$name (no suite found in Tests; the check has lost its subject)"
  elif [ -z "$report" ]; then
    pass "$name"
  else
    fail "$name"; printf '%s\n' "$report"
  fi
}

# Prohibition. Local-only files are never force-added. Not self-tested: it reads the real index.
check_nothing_local_tracked() {
  local name="no local-only file is tracked"
  local hits
  hits=$(cd "$ROOT" && git ls-files -- CLAUDE.md AGENTS.md GEMINI.md .agents .claude .codex .gemini plans 2>/dev/null || true)
  if [ -z "$hits" ]; then pass "$name"; else fail "$name"; printf '%s\n' "$hits"; fi
}

# Prohibition. The format gate. An absent tool is a failure, never a skip. Not self-tested: it needs
# the toolchain and its rules are swift-format's to prove.
check_format() {
  local name="swift format lint --strict reports zero findings"
  if ! command -v swift >/dev/null 2>&1; then fail "$name (swift toolchain not found)"; return; fi
  if (cd "$ROOT" && swift format lint --strict --recursive Sources Tests >/dev/null 2>&1); then
    pass "$name"
  else
    fail "$name"
    (cd "$ROOT" && swift format lint --strict --recursive Sources Tests 2>&1 | head -40)
  fi
}

# The checks --self-test can plant a violation for, in run order.
SELF_TESTABLE=(
  check_force_ops
  check_models_foundation_import
  check_models_import_boundary
  check_banned_imports
  check_wall_clock_and_locks
  check_unsafe
  check_darwin_guard
  check_coordinates
  check_em_dash
  check_test_jargon
  check_swift_testing_only
  check_job_timeouts
  check_suite_time_limit
)

run_all() {
  for check in "${SELF_TESTABLE[@]}"; do "$check"; done
  check_nothing_local_tracked
  check_format
}

# ---------------------------------------------------------------------------------------------------
# Self-test. A clean synthesized tree that every check passes, then one planted violation per check.
# ---------------------------------------------------------------------------------------------------

write_clean_tree() {
  # $1: directory
  local d="$1"
  mkdir -p "$d/Sources/SwiftNARACatalogBulkModels" "$d/Sources/SwiftNARACatalogBulk" "$d/Sources/SwiftNARACatalogBulkTestSupport/Fixtures" "$d/Tests/SwiftNARACatalogBulkModelsTests" "$d/Tests/SwiftNARACatalogBulkTests" "$d/Scripts"
  # A recorded response body, carrying the provider's own em dash and the provider's own "seams", so
  # the clean arm fails if either scan stops skipping recordings. Written with an escape because the
  # em-dash check reads this script too.
  printf '{\n  "glossary": [\n    {\n      "term": "Abutment seepage",\n      "definition": "Water that moves through seams in the abutment \342\200\224 and exits downstream."\n    }\n  ]\n}\n' > "$d/Sources/SwiftNARACatalogBulkTestSupport/Fixtures/Glossary.json"
  # The doc comment names what the code may not, and the type name starts with an SDK module's name,
  # so the clean arm fails if either the comment filter or the word boundary stops holding.
  cat > "$d/Sources/SwiftNARACatalogBulkModels/MediaType.swift" <<'EOF'
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// A media type. The doc comment may say Date(), unsafe, import HTTPCore, and URLSession.
public struct MediaType: Sendable {
  public let rawValue: String
}

public typealias SwiftNARACatalogBulkModelsVersion = Int
EOF
  cat > "$d/Sources/SwiftNARACatalogBulk/Client.swift" <<'EOF'
import HTTPCore
import SwiftNARACatalogBulkModels

public struct Client: Sendable {}
EOF
  cat > "$d/Sources/SwiftNARACatalogBulk/Client+URLSession.swift" <<'EOF'
#if canImport(Darwin)
import Foundation
import HTTPURLSession

extension Client {}
#endif
EOF
  # The suite here is written in the wrapped shape swift-format produces for a long attribute, so
  # the clean-tree arm fails if the scan stops reading at the end of the first line.
  cat > "$d/Tests/SwiftNARACatalogBulkModelsTests/MediaTypeTests.swift" <<'EOF'
import SwiftNARACatalogBulkModels
import Testing

@Suite(
  "MediaType", .timeLimit(.minutes(suiteTimeLimitMinutes)))
struct MediaTypeTests {
  @Test func aMediaTypeKeepsItsString() {
    #expect(true)
  }
}
EOF
  cat > "$d/Tests/SwiftNARACatalogBulkTests/ClientTests.swift" <<'EOF'
import SwiftNARACatalogBulk
import SwiftNARACatalogBulkModels
import Testing

@Suite(.timeLimit(.minutes(suiteTimeLimitMinutes))) struct ClientTests {
  @Test func aClientIsMade() {
    #expect(true)
  }
}
EOF
  mkdir -p "$d/.github/workflows"
  cat > "$d/.github/workflows/ci.yml" <<'EOF'
name: CI

on:
  push:
    branches: [main]
  pull_request:

jobs:
  linux:
    runs-on: ubuntu-latest
    timeout-minutes: 15
    steps:
      - uses: actions/checkout@v7

  lint:
    runs-on: ubuntu-latest
    timeout-minutes: 10
    steps:
      - uses: actions/checkout@v7
EOF
  cat > "$d/.github/workflows/docs.yml" <<'EOF'
name: Docs

on:
  push:
    branches: [main]

permissions:
  contents: read

jobs:
  build:
    runs-on: macos-26
    timeout-minutes: 15
    steps:
      - uses: actions/checkout@v7
EOF
  printf '# Readme\n' > "$d/README.md"
  printf '# Changelog\n' > "$d/CHANGELOG.md"
  printf '# Contributing\n' > "$d/CONTRIBUTING.md"
  printf 'version: 1\n' > "$d/.spi.yml"
  printf '// swift-tools-version: 6.2\n' > "$d/Package.swift"
}

# Runs one check against $1 and echoes its outcome as PASS or FAIL, swallowing output.
outcome_of() {
  # $1: directory, $2: check function
  local saved="$FAILURES" result
  FAILURES=0
  ROOT="$1" "$2" >/dev/null 2>&1
  if [ "$FAILURES" -eq 0 ]; then result=PASS; else result=FAIL; fi
  FAILURES="$saved"
  printf '%s' "$result"
}

# One negative per check: the smallest edit that must trip it.
plant_violation() {
  # $1: directory, $2: check function
  local d="$1"
  case "$2" in
    check_force_ops)
      printf 'let x = y as! Int\n' >> "$d/Sources/SwiftNARACatalogBulk/Client.swift" ;;
    check_models_foundation_import)
      printf 'import Foundation\n' > "$d/Sources/SwiftNARACatalogBulkModels/Unguarded.swift" ;;
    check_models_import_boundary)
      printf 'import HTTPCore\n' > "$d/Sources/SwiftNARACatalogBulkModels/Leak.swift" ;;
    check_banned_imports)
      printf 'import Combine\n' >> "$d/Sources/SwiftNARACatalogBulkModels/MediaType.swift" ;;
    check_wall_clock_and_locks)
      printf 'let now = Date()\n' >> "$d/Sources/SwiftNARACatalogBulkModels/MediaType.swift" ;;
    check_unsafe)
      printf 'let n = unsafe ptr.load()\n' >> "$d/Sources/SwiftNARACatalogBulk/Client.swift" ;;
    check_darwin_guard)
      printf 'import HTTPURLSession\n\nextension Client {}\n' > "$d/Sources/SwiftNARACatalogBulk/Unguarded.swift" ;;
    check_coordinates)
      printf '// Added in P3\055T2 for Ph\141se 4\n' >> "$d/Sources/SwiftNARACatalogBulkModels/MediaType.swift" ;;
    check_em_dash)
      printf 'A line \342\200\224 with an em dash\n' >> "$d/README.md" ;;
    check_test_jargon)
      printf 'Swap in a test double here.\n' >> "$d/README.md" ;;
    check_swift_testing_only)
      printf 'import XCTest\n' >> "$d/Tests/SwiftNARACatalogBulkModelsTests/MediaTypeTests.swift" ;;
    check_job_timeouts)
      printf 'name: Extra\n\non:\n  push:\n\njobs:\n  stray:\n    runs-on: ubuntu-latest\n    steps:\n      - uses: actions/checkout@v7\n' > "$d/.github/workflows/extra.yml" ;;
    check_suite_time_limit)
      printf 'import Testing\n\n@Suite struct UnboundedTests {\n  @Test func aTestRuns() {\n    #expect(true)\n  }\n}\n' > "$d/Tests/SwiftNARACatalogBulkTests/UnboundedTests.swift" ;;
  esac
}

# A further negative for a check whose subject has more than one shape to recognize: one violation in
# the second shape, which must also fail.
plant_second_violation() {
  # $1: directory, $2: check function; returns 1 when the check has one shape only
  local d="$1"
  case "$2" in
    # An attribute and an access level in front of the import do not make it another import.
    check_models_import_boundary)
      printf '@_exported public import HTTPURLSession\n' > "$d/Sources/SwiftNARACatalogBulkModels/Leak.swift" ;;
    # A test file is as Darwin-only as a source file, and `@testable` is still an import.
    check_darwin_guard)
      printf '@testable import HTTPURLSession\nimport Testing\n' > "$d/Tests/SwiftNARACatalogBulkTests/Unguarded.swift" ;;
    # Skipping recordings does not skip the Swift written beside them: a doc comment is user-facing
    # prose, and `Sources` is where most of it lives.
    check_em_dash)
      printf '/// A summary \342\200\224 with an em dash in it.\n' >> "$d/Sources/SwiftNARACatalogBulkModels/MediaType.swift" ;;
    # Same shape for the jargon scan, in the module whose vocabulary the rule is about.
    check_test_jargon)
      printf '/// Swap in a test double here.\n' >> "$d/Sources/SwiftNARACatalogBulk/Client.swift" ;;
    # A key indented into a step bounds that step, not the job, so the job is still unbounded.
    check_job_timeouts)
      printf 'name: Nested\n\non:\n  push:\n\njobs:\n  nested:\n    runs-on: ubuntu-latest\n    steps:\n      - uses: actions/checkout@v7\n        timeout-minutes: 5\n' > "$d/.github/workflows/nested.yml" ;;
    # A suite nested inside a bounded one is indented, so a scan anchored at the margin would not
    # see it. The outer suite carries the limit; the inner one does not.
    check_suite_time_limit)
      printf 'import SwiftNARACatalogBulkModels\nimport Testing\n\n@Suite(.timeLimit(.minutes(suiteTimeLimitMinutes))) struct OuterTests {\n  @Suite struct NestedTests {\n    @Test func aTestRuns() {\n      #expect(true)\n    }\n  }\n}\n' > "$d/Tests/SwiftNARACatalogBulkTests/NestedTests.swift" ;;
    *) return 1 ;;
  esac
}

# A third negative for a check whose subject has a third shape to recognize, which must also fail.
plant_third_violation() {
  # $1: directory, $2: check function; returns 1 when the check has fewer than three shapes
  local d="$1"
  case "$2" in
    # Importing one declaration is still importing the module.
    check_models_import_boundary)
      printf 'import struct HTTPCore.Request\n' > "$d/Sources/SwiftNARACatalogBulkModels/Leak.swift" ;;
    # A quoted job name is still a job. Failing to recognize it would hide the job rather than
    # report it, which is the one way this check can go quiet instead of loud.
    check_job_timeouts)
      printf 'name: Quoted\n\non:\n  push:\n\njobs:\n  "quoted":\n    runs-on: ubuntu-latest\n    steps:\n      - uses: actions/checkout@v7\n' > "$d/.github/workflows/quoted.yml" ;;
    # A suite is still a suite when another attribute precedes it on the line.
    check_suite_time_limit)
      printf 'import Testing\n\n@MainActor @Suite struct PrefixedTests {\n  @Test func aTestRuns() {\n    #expect(true)\n  }\n}\n' > "$d/Tests/SwiftNARACatalogBulkTests/PrefixedTests.swift" ;;
    *) return 1 ;;
  esac
}

# A fourth negative, for a check whose subject has a fourth shape to recognize.
plant_fourth_violation() {
  # $1: directory, $2: check function; returns 1 when the check has fewer than four shapes
  local d="$1"
  case "$2" in
    # URLSession is Foundation's, so no import names it; the use itself is the violation.
    check_models_import_boundary)
      printf 'let session = URLSession.shared\n' >> "$d/Sources/SwiftNARACatalogBulkModels/MediaType.swift" ;;
    # Naming the constant in a comment is not carrying the trait.
    check_suite_time_limit)
      printf 'import Testing\n\n@Suite struct CommentedTests {  // suiteTimeLimitMinutes\n  @Test func aTestRuns() {\n    #expect(true)\n  }\n}\n' > "$d/Tests/SwiftNARACatalogBulkTests/CommentedTests.swift" ;;
    *) return 1 ;;
  esac
}

# A fifth negative, for a check whose subject has a fifth shape to recognize.
plant_fifth_violation() {
  # $1: directory, $2: check function; returns 1 when the check has fewer than five shapes
  local d="$1"
  case "$2" in
    # The SDK depends on the models, so the models importing the SDK closes a cycle.
    check_models_import_boundary)
      printf 'import SwiftNARACatalogBulk\n' > "$d/Sources/SwiftNARACatalogBulkModels/Leak.swift" ;;
    # A test at file scope is in an implicit suite no attribute reaches, so no suite bounds it.
    check_suite_time_limit)
      printf 'import Testing\n\n@Test func aTestAtFileScopeRuns() {\n  #expect(true)\n}\n' > "$d/Tests/SwiftNARACatalogBulkTests/FileScopeTests.swift" ;;
    *) return 1 ;;
  esac
}

# A further negative for each check that guards its subject: remove the subject, which must also fail.
remove_subject() {
  # $1: directory, $2: check function; returns 1 when the check has no subject to remove
  local d="$1"
  case "$2" in
    check_models_foundation_import | check_models_import_boundary)
      rm -rf "$d/Sources/SwiftNARACatalogBulkModels" ;;
    check_darwin_guard)
      rm -f "$d/Sources/SwiftNARACatalogBulk/Client+URLSession.swift" ;;
    check_swift_testing_only)
      printf 'import SwiftNARACatalogBulkModels\n' > "$d/Tests/SwiftNARACatalogBulkModelsTests/MediaTypeTests.swift"
      printf 'import SwiftNARACatalogBulk\n' > "$d/Tests/SwiftNARACatalogBulkTests/ClientTests.swift" ;;
    check_job_timeouts)
      rm -rf "$d/.github" ;;
    # The tree keeps its test files and loses every suite, so the arm proves the empty derived set
    # fails on its own rather than on a file-scope test the check also refuses.
    check_suite_time_limit)
      printf 'import SwiftNARACatalogBulkModels\nimport Testing\n\nstruct NotASuite {}\n' > "$d/Tests/SwiftNARACatalogBulkModelsTests/MediaTypeTests.swift"
      printf 'import SwiftNARACatalogBulk\nimport Testing\n\nstruct NotASuite {}\n' > "$d/Tests/SwiftNARACatalogBulkTests/ClientTests.swift" ;;
    *) return 1 ;;
  esac
}

self_test() {
  local scratch clean planted got arms=0
  scratch=$(mktemp -d "${TMPDIR:-/tmp}/verify-self-test.XXXXXX")
  # Expanded now: the trap runs after this function's locals are gone.
  trap "rm -rf '$scratch'" EXIT

  clean="$scratch/clean"
  write_clean_tree "$clean"
  for check in "${SELF_TESTABLE[@]}"; do
    got=$(outcome_of "$clean" "$check")
    arms=$((arms + 1))
    if [ "$got" = PASS ]; then pass "self-test: $check passes a clean tree"; else fail "self-test: $check FAILED a clean tree"; fi
  done

  for check in "${SELF_TESTABLE[@]}"; do
    planted="$scratch/planted-$check"
    write_clean_tree "$planted"
    plant_violation "$planted" "$check"
    got=$(outcome_of "$planted" "$check")
    arms=$((arms + 1))
    if [ "$got" = FAIL ]; then pass "self-test: $check trips on its planted violation"; else fail "self-test: $check MISSED its planted violation"; fi

    planted="$scratch/second-$check"
    write_clean_tree "$planted"
    if plant_second_violation "$planted" "$check"; then
      got=$(outcome_of "$planted" "$check")
      arms=$((arms + 1))
      if [ "$got" = FAIL ]; then pass "self-test: $check trips on its second planted violation"; else fail "self-test: $check MISSED its second planted violation"; fi
    fi

    planted="$scratch/third-$check"
    write_clean_tree "$planted"
    if plant_third_violation "$planted" "$check"; then
      got=$(outcome_of "$planted" "$check")
      arms=$((arms + 1))
      if [ "$got" = FAIL ]; then pass "self-test: $check trips on its third planted violation"; else fail "self-test: $check MISSED its third planted violation"; fi
    fi

    planted="$scratch/fourth-$check"
    write_clean_tree "$planted"
    if plant_fourth_violation "$planted" "$check"; then
      got=$(outcome_of "$planted" "$check")
      arms=$((arms + 1))
      if [ "$got" = FAIL ]; then pass "self-test: $check trips on its fourth planted violation"; else fail "self-test: $check MISSED its fourth planted violation"; fi
    fi

    planted="$scratch/fifth-$check"
    write_clean_tree "$planted"
    if plant_fifth_violation "$planted" "$check"; then
      got=$(outcome_of "$planted" "$check")
      arms=$((arms + 1))
      if [ "$got" = FAIL ]; then pass "self-test: $check trips on its fifth planted violation"; else fail "self-test: $check MISSED its fifth planted violation"; fi
    fi

    planted="$scratch/subjectless-$check"
    write_clean_tree "$planted"
    if remove_subject "$planted" "$check"; then
      got=$(outcome_of "$planted" "$check")
      arms=$((arms + 1))
      if [ "$got" = FAIL ]; then pass "self-test: $check fails when its subject is gone"; else fail "self-test: $check PASSED with its subject gone"; fi
    fi
  done
  printf '%d self-test arms\n' "$arms"
}

# ---------------------------------------------------------------------------------------------------

case "${1:-}" in
  "") run_all ;;
  --self-test) self_test ;;
  *) printf 'usage: %s [--self-test]\n' "$0" >&2; exit 2 ;;
esac

if [ "$FAILURES" -eq 0 ]; then exit 0; fi
printf '%d check(s) failed\n' "$FAILURES"
exit 1
