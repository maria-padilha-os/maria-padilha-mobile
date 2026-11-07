#!/usr/bin/env bash
# Repository hygiene and build-scaffold checks.

set -euo pipefail

root=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
cd "$root"
fail=0

if [ ! -s README.md ]; then
  echo "FAIL README.md missing"
  fail=1
else
  echo "ok README.md"
fi

if grep -q 'scripts/build.sh' README.md; then
  echo "ok README documents the build entry point"
else
  echo "FAIL README does not document scripts/build.sh"
  fail=1
fi

if git diff --check HEAD; then
  echo "ok no whitespace errors in the working diff"
else
  echo "FAIL whitespace errors in the working diff"
  fail=1
fi

if bash tests/build.sh; then
  echo "ok tests/build.sh"
else
  echo "FAIL tests/build.sh"
  fail=1
fi

if git ls-files | grep -qE '^(out|\.scratch)/'; then
  echo "FAIL build output is tracked"
  fail=1
else
  echo "ok no tracked build output"
fi

[ "$fail" -eq 0 ]
